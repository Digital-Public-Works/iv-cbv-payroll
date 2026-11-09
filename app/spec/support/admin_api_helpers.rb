# Helpers for admin API request specs: signed requests and a complete, valid
# partner to work on.
module AdminApiHelpers
  ADMIN_API_TEST_SECRET = "test-admin-api-secret".freeze
  ADMIN_API_TEST_ACTOR = "operator@digitalpublicworks.org".freeze

  # Sends a VMI-ADMIN-HMAC-V1 signed request. `body` is sent as raw JSON;
  # `raw_body` sends a string as is (e.g. malformed JSON).
  def admin_request(method, path, body: nil, raw_body: nil, query: "", actor: ADMIN_API_TEST_ACTOR)
    raw = raw_body || (body.nil? ? "" : JSON.generate(body))
    timestamp = Time.now.to_i
    headers = {
      "X-VMI-Admin-Signature" => AdminApi::RequestSignature.sign(
        ADMIN_API_TEST_SECRET, method: method.to_s.upcase, path: path, query: query, timestamp: timestamp, body: raw, actor: actor
      ),
      "X-VMI-Admin-Timestamp" => timestamp.to_s,
      "X-VMI-Admin-Actor" => actor,
      "CONTENT_TYPE" => "application/json"
    }
    url = query.present? ? "#{path}?#{query}" : path
    send(method, url, params: raw.presence, headers: headers)
  end

  def json_body
    JSON.parse(response.body)
  end

  # Runs the example with the admin API on, and settings writable (demo) or
  # read-only (prod).
  def with_admin_api(settings_writable:, &block)
    stub_environment_variable("ADMIN_API_SERVICE_SECRET", ADMIN_API_TEST_SECRET) do
      stub_environment_variable("ADMIN_API_SETTINGS_WRITABLE", settings_writable ? "true" : nil, &block)
    end
  end

  def admin_settings_document(partner_id = "admin_spec")
    {
      "partner_id" => partner_id,
      "name" => "Admin Spec Agency",
      "timezone" => "America/New_York",
      "domain" => partner_id.tr("_", "-"),
      "active_demo" => true,
      "active_prod" => false,
      "invitation_links_enabled" => true,
      "pay_income_days_w2" => 90,
      "pay_income_days_gig" => 90,
      "partner_identifier_name" => "case_number",
      "application_attributes" => [
        { "name" => "case_number", "data_type" => "string", "validation_regex" => "\\A\\d{8}\\z", "required_for_submit" => true },
        { "name" => "first_name", "data_type" => "string", "description" => "First name" }
      ],
      "invitation_attributes" => [ { "name" => "case_number", "required" => true }, { "name" => "first_name", "required" => false } ],
      "landing_page_attributes" => [],
      "applicant_input_page" => [ { "name" => "first_name", "required" => true } ],
      "translations" => {
        "en" => { "shared.agency_full_name" => "Admin Spec", "shared.header.cbv_flow_title" => "Title", "shared.header.preheader" => "Pre" },
        "es" => { "shared.agency_full_name" => "Admin Spec", "shared.header.cbv_flow_title" => "Título", "shared.header.preheader" => "Pre" }
      }
    }
  end

  def admin_credentials_document(partner_id = "admin_spec", password: "stored-sftp-password")
    {
      "partner_id" => partner_id,
      "argyle_environment" => "sandbox",
      "weekly_report_recipients" => "ops@example.org",
      "transmission_methods" => [
        {
          "method_type" => "sftp",
          "configs" => [
            { "key" => "url", "value" => "sftp.example.org", "encrypted" => false },
            { "key" => "user", "value" => "agency", "encrypted" => false },
            { "key" => "password", "value" => password, "encrypted" => true },
            { "key" => "path_prefix", "value" => "inbox", "encrypted" => false }
          ]
        }
      ]
    }
  end

  def create_admin_partner!(partner_id = "admin_spec", settings: admin_settings_document(partner_id), credentials: admin_credentials_document(partner_id))
    loader = PartnerConfigLoader.from_documents(settings, credentials).validate!
    raise "invalid test partner: #{loader.errors.join('; ')}" unless loader.valid?
    loader.apply!
    PartnerConfig.find_by!(partner_id: partner_id)
  end

  def stored_secret(partner_id, method_type, key)
    PartnerConfig.find_by!(partner_id: partner_id).partner_transmission_methods
      .find { |m| m.method_type == method_type }&.partner_transmission_configs&.find { |c| c.key == key }
  end

  def admin_version(partner_id)
    AdminApi::PartnerDocuments.version(PartnerConfig.find_by!(partner_id: partner_id))
  end
end

RSpec.configure do |config|
  config.include AdminApiHelpers, type: :request
  config.include AdminApiHelpers, type: :admin_api
end
