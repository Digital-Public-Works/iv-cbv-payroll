require "rails_helper"

RSpec.describe "Admin API: reading partners", type: :request do
  around { |example| with_admin_api(settings_writable: false) { example.run } }

  before { create_admin_partner! }

  describe "GET /api/admin/v1/partners/:partner_id" do
    it "returns both documents with secrets masked, and the version token" do
      admin_request(:get, "/api/admin/v1/partners/admin_spec")

      expect(response).to have_http_status(:ok)
      body = json_body
      expect(body.keys).to contain_exactly("partner_id", "updated_at", "settings", "credentials")
      expect(body["updated_at"]).to eq(admin_version("admin_spec"))
      expect(body["settings"]).to include("name" => "Admin Spec Agency", "pay_income_days_w2" => 90)
      expect(body["settings"]["invitation_attributes"]).to eq([ { "name" => "case_number", "required" => true }, { "name" => "first_name", "required" => false } ])
      expect(body["credentials"].keys).to contain_exactly("partner_id", "argyle_environment", "weekly_report_recipients", "transmission_methods")
      password = body["credentials"]["transmission_methods"][0]["configs"].find { |c| c["key"] == "password" }
      expect(password).to eq("key" => "password", "value" => "$ENCRYPTED", "encrypted" => true)
      expect(response.body).not_to include("stored-sftp-password")
    end

    it "returns 404 for an unknown partner" do
      admin_request(:get, "/api/admin/v1/partners/nope")

      expect(response).to have_http_status(:not_found)
      expect(json_body["message"]).to include("nope")
    end
  end

  describe "GET /api/admin/v1/schema" do
    it "describes every scalar with its partition, and each method's keys" do
      admin_request(:get, "/api/admin/v1/schema")

      expect(response).to have_http_status(:ok)
      body = json_body
      by_name = body["scalars"].index_by { |f| f["name"] }
      expect(by_name.keys).to match_array(PartnerConfigLoader::SETTINGS_ATTRS + %w[argyle_environment weekly_report_recipients])
      expect(by_name["name"]).to include("type" => "string", "required" => true, "partition" => "settings")
      expect(by_name["active_prod"]).to include("type" => "boolean", "default" => false)
      expect(by_name["encourage_link_sharing"]).to include("default" => true)
      expect(by_name["pay_income_days_w2"]).to include("type" => "enum", "enum" => [ 90, 182 ])
      expect(by_name["argyle_environment"]).to include("partition" => "credentials", "enum" => %w[sandbox production], "required" => true)
      expect(by_name["weekly_report_recipients"]).to include("type" => "text")

      expect(body["application_attribute_fields"].map { |f| f["name"] }).to eq(PartnerConfigLoader::APPLICATION_ATTRIBUTE_KEYS)
      expect(body["usage_sections"].map { |s| s["name"] }).to eq(PartnerConfigLoader::ATTRIBUTE_USAGE_SECTIONS.keys)

      sftp = body["transmission_methods"].find { |m| m["method_type"] == "sftp" }
      expect(sftp["keys"].map { |k| k["key"] }).to eq(%w[url user password path_prefix port])
      expect(sftp["keys"].find { |k| k["key"] == "password" }).to include("required" => true, "encrypted" => true)
      expect(sftp["keys"].find { |k| k["key"] == "path_prefix" }).to include("blank_allowed" => true)
      expect(body["transmission_methods"].map { |m| m["method_type"] }).to match_array(PartnerConfigLoader::VALID_TRANSMISSION_METHODS)
      expect(body["reserved_names"]).to include("admin", "static")
    end
  end

  describe "GET /api/admin/v1/partners/:partner_id/export" do
    it "returns the rake task's two files, with secrets masked" do
      admin_request(:get, "/api/admin/v1/partners/admin_spec/export", query: "include_secrets=false")

      expect(response).to have_http_status(:ok)
      files = json_body["files"]
      expect(files["settings"]["filename"]).to eq("admin_spec.settings.yml")
      expect(files["credentials"]["filename"]).to eq("admin_spec.credentials.#{Rails.env}.yml")
      docs = PartnerConfigLoader.export("admin_spec")
      expect(files["settings"]["content"]).to eq(docs[:settings].to_yaml)
      expect(files["credentials"]["content"]).to eq(docs[:credentials].to_yaml)
      expect(response.body).not_to include("stored-sftp-password")
    end

    it "decrypts secrets for an export with secrets, and logs it" do
      allow(Rails.logger).to receive(:info).and_call_original

      admin_request(:get, "/api/admin/v1/partners/admin_spec/export", query: "include_secrets=true")

      credentials = YAML.safe_load(json_body["files"]["credentials"]["content"])
      password = credentials["transmission_methods"][0]["configs"].find { |c| c["key"] == "password" }
      expect(password).to eq("key" => "password", "encrypted" => true, "value" => "stored-sftp-password")
      expect(Rails.logger).to have_received(:info).with(a_string_including("action=export_with_secrets", "partner=admin_spec"))
    end

    it "round-trips: an export with secrets re-applies to identical config" do
      admin_request(:get, "/api/admin/v1/partners/admin_spec/export", query: "include_secrets=true")
      files = json_body["files"]
      before = PartnerConfigLoader.export("admin_spec", include_secrets: true)

      # Break it, then put the export back.
      changed = admin_settings_document.merge("name" => "Broken")
      PartnerConfigLoader.from_documents(changed, admin_credentials_document(password: "other")).validate!.apply!
      loader = PartnerConfigLoader.from_documents(YAML.safe_load(files["settings"]["content"]), YAML.safe_load(files["credentials"]["content"]))
      loader.validate!.apply!

      expect(PartnerConfigLoader.export("admin_spec", include_secrets: true)).to eq(before)
      expect(stored_secret("admin_spec", "sftp", "password").is_encrypted).to be(true)
    end
  end

  describe "GET /api/admin/v1/export" do
    it "exports every partner" do
      admin_request(:get, "/api/admin/v1/export", query: "include_secrets=false")

      expect(response).to have_http_status(:ok)
      ids = json_body["partners"].map { |p| p["partner_id"] }
      expect(ids).to eq(PartnerConfig.order(:partner_id).pluck(:partner_id))
      expect(response.body).not_to include("stored-sftp-password")
    end
  end
end
