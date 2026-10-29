class Api::Admin::V1::PartnersController < Api::Admin::V1::BaseController
  before_action :find_partner, only: %i[show update validate diff export]

  # Reads straight from the database (not the cache)
  def index
    partners = PartnerConfig.includes(:partner_transmission_methods).order(:partner_id)

    render json: {
      partners: partners.map { |partner| partner_summary(partner) },
      meta: { settings_writable: AdminApi::Config.settings_writable? }
    }
  end

  def show
    render_detail(@partner)
  end

  # Settings and credentials documents for a new partner.
  # for prod settings, have to promote from demo
  def create
    settings = body_json["settings"]
    partner_id = settings.is_a?(Hash) ? settings["partner_id"].to_s : nil
    logged("create", partner_id: partner_id) do
      writes.create(settings, body_json["credentials"])
      render_detail(PartnerConfig.find_by!(partner_id: partner_id))
    end
  end

  # Partial update
  def update
    changed = %w[settings credentials].flat_map { |doc| (body_json[doc].is_a?(Hash) ? body_json[doc].keys : []) }
    logged("update", partner_id: @partner.partner_id, changed: changed) do
      writes.update(@partner, body_json.slice("settings", "credentials"), expected_version: body_json["updated_at"])
      render_detail(@partner)
    end
  end

  def validate
    loader = writes.candidate(@partner, body_json.slice("settings", "credentials"))
    render json: { valid: loader.valid?, errors: loader.error_details, warnings: loader.warning_details }
  end

  def diff
    loader = writes.candidate(@partner, body_json.slice("settings", "credentials"))
    render json: { diff: writes.diff(@partner, loader) }
  end

  def export
    include_secrets = params[:include_secrets] == "true"
    if include_secrets
      logged("export_with_secrets", partner_id: @partner.partner_id) do
        render json: AdminApi::PartnerDocuments.export_files(@partner.partner_id, include_secrets: true)
      end
    else
      render json: AdminApi::PartnerDocuments.export_files(@partner.partner_id)
    end
  end

  # promote from demo to prod
  def promote_settings
    return head(:not_found) if AdminApi::Config.settings_writable?

    partner_id = params[:partner_id]
    created = !PartnerConfig.exists?(partner_id: partner_id)
    logged("promote_settings", partner_id: partner_id, changed: [ "settings" ],
           created: created, source_fingerprint: body_json["source_fingerprint"].to_s.first(64)) do
      writes.promote_settings(partner_id, body_json["settings"],
        credentials: body_json["credentials"], expected_version: body_json["expected_prod_updated_at"])
      render_detail(PartnerConfig.find_by!(partner_id: partner_id))
    end
  end

  private

  def writes
    @writes ||= AdminApi::PartnerWrites.new
  end

  def partner_summary(partner)
    {
      partner_id: partner.partner_id,
      name: partner.name,
      active_demo: partner.active_demo,
      active_prod: partner.active_prod,
      transmission_methods: partner.partner_transmission_methods.map(&:method_type).sort,
      updated_at: partner.updated_at.iso8601(6)
    }
  end
end
