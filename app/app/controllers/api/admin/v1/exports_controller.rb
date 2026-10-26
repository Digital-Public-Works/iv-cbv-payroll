class Api::Admin::V1::ExportsController < Api::Admin::V1::BaseController
  # export, allows including of secret values if explicity specified
  def index
    include_secrets = params[:include_secrets] == "true"
    export = lambda do
      partner_ids = PartnerConfig.order(:partner_id).pluck(:partner_id)
      render json: { partners: partner_ids.map { |id| AdminApi::PartnerDocuments.export_files(id, include_secrets: include_secrets) } }
    end
    include_secrets ? logged("export_all_with_secrets", partner_id: "all", &export) : export.call
  end
end
