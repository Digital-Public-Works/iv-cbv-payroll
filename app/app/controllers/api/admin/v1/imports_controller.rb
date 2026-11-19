class Api::Admin::V1::ImportsController < Api::Admin::V1::BaseController
  # import a config, validate, and show diff. Allow for dry-run that does the validation and diff without making changes.
  # send feedback back to caller
  def create
    dry_run = body_json["dry_run"] != false
    params_for = {
      settings_yaml: body_json["settings_yaml"].presence,
      credentials_yaml: body_json["credentials_yaml"].presence,
      expected_version: body_json["expected_updated_at"],
      confirm_deletes: body_json["confirm_deletes"] == true,
      dry_run: dry_run
    }
    documents = [ params_for[:settings_yaml] && "settings", params_for[:credentials_yaml] && "credentials" ].compact

    if dry_run
      render json: response_for(AdminApi::PartnerWrites.new.import(**params_for), applied: false)
    else
      result = nil
      logged("import", partner_id: partner_id_hint, changed: documents) do
        result = AdminApi::PartnerWrites.new.import(**params_for)
      end
      render json: response_for(result, applied: true)
    end
  end

  private

  def response_for(result, applied:)
    loader = result.loader
    partner_id = loader.yaml_data[:partner_id].to_s
    partner = PartnerConfig.find_by(partner_id: partner_id)
    {
      valid: loader.valid?,
      errors: loader.error_details,
      warnings: loader.warning_details,
      partner_id: partner_id,
      exists: result.existed,
      updated_at: partner && AdminApi::PartnerDocuments.version(partner),
      diff: result.diff,
      applied: applied
    }
  end

  # For the log line only; the import service works out the real partner_id.
  def partner_id_hint
    [ body_json["settings_yaml"], body_json["credentials_yaml"] ].each do |yaml|
      match = yaml.to_s.match(/^partner_id:\s*['"]?([\w-]+)/)
      return match[1] if match
    end
    nil
  end
end
