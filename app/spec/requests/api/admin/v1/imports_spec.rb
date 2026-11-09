require "rails_helper"

RSpec.describe "Admin API: import config", type: :request do
  let(:path) { "/api/admin/v1/partners/import" }
  let!(:partner) { create_admin_partner! }
  let(:settings_writable) { true }

  around { |example| with_admin_api(settings_writable: settings_writable) { example.run } }

  def export_yaml(include_secrets: false)
    docs = PartnerConfigLoader.export("admin_spec", include_secrets: include_secrets)
    [ docs[:settings].to_yaml, docs[:credentials].to_yaml ]
  end

  def import(settings_yaml: nil, credentials_yaml: nil, dry_run: false, confirm_deletes: false, expected_updated_at: admin_version("admin_spec"))
    admin_request(:post, path, body: { settings_yaml: settings_yaml, credentials_yaml: credentials_yaml, dry_run: dry_run,
                                       confirm_deletes: confirm_deletes, expected_updated_at: expected_updated_at })
  end

  it "previews an import as a dry run without writing" do
    settings, credentials = export_yaml
    import(settings_yaml: settings.sub("Admin Spec Agency", "Renamed"), credentials_yaml: credentials, dry_run: true)

    expect(response).to have_http_status(:ok)
    expect(json_body).to include("valid" => true, "exists" => true, "partner_id" => "admin_spec", "applied" => false,
                                 "updated_at" => admin_version("admin_spec"))
    expect(json_body["diff"]["settings"]["scalars"]).to eq([ { "key" => "name", "before" => "Admin Spec Agency", "after" => "Renamed" } ])
    expect(json_body["diff"]["credentials"]["transmission_methods"]).to eq([])
    expect(partner.reload.name).to eq("Admin Spec Agency")
  end

  it "answers a dry run with every validation problem, still 200" do
    settings, credentials = export_yaml
    import(settings_yaml: settings.sub("pay_income_days_w2: 90", "pay_income_days_w2: 30"), credentials_yaml: credentials, dry_run: true)

    expect(response).to have_http_status(:ok)
    expect(json_body["valid"]).to be(false)
    expect(json_body["errors"]).to include(a_hash_including("path" => "pay_income_days_w2"))
  end

  it "puts a masked export back, keeping the stored secrets" do
    settings, credentials = export_yaml
    PartnerConfigLoader.from_documents(admin_settings_document.merge("name" => "Broken"), admin_credentials_document).validate!.apply!

    import(settings_yaml: settings, credentials_yaml: credentials)

    expect(response).to have_http_status(:ok)
    expect(json_body["applied"]).to be(true)
    expect(partner.reload.name).to eq("Admin Spec Agency")
    expect(stored_secret("admin_spec", "sftp", "password").value).to eq("stored-sftp-password")
  end

  it "applies an export with secrets as-is" do
    settings, credentials = export_yaml(include_secrets: true)
    PartnerConfigLoader.from_documents(admin_settings_document, admin_credentials_document(password: "changed")).validate!.apply!

    import(settings_yaml: settings, credentials_yaml: credentials)

    expect(stored_secret("admin_spec", "sftp", "password").value).to eq("stored-sftp-password")
  end

  it "ignores the portal's comment header" do
    settings, credentials = export_yaml
    header = "# vmi-admin export · env=demo · partner=admin_spec · secrets=no\n"
    import(settings_yaml: header + settings, credentials_yaml: header + credentials, dry_run: true)

    expect(json_body["valid"]).to be(true)
  end

  it "requires confirming deletes" do
    settings, = export_yaml
    trimmed = YAML.safe_load(settings)
    trimmed["translations"]["es"].delete("shared.header.preheader")

    import(settings_yaml: trimmed.to_yaml)
    expect(response).to have_http_status(:unprocessable_content)
    expect(json_body["deletes"]).to eq([ { "section" => "translations", "name" => "es: shared.header.preheader" } ])
    expect(partner.reload.partner_translations.count).to eq(6)

    import(settings_yaml: trimmed.to_yaml, confirm_deletes: true)
    expect(response).to have_http_status(:ok)
    expect(partner.reload.partner_translations.count).to eq(5)
  end

  it "imports settings alone, leaving credentials untouched" do
    settings, = export_yaml
    import(settings_yaml: settings.sub("Admin Spec Agency", "Renamed"))

    expect(response).to have_http_status(:ok)
    expect(partner.reload.name).to eq("Renamed")
    expect(stored_secret("admin_spec", "sftp", "password").value).to eq("stored-sftp-password")
  end

  it "imports credentials alone, leaving settings untouched" do
    _, credentials = export_yaml
    import(credentials_yaml: credentials.sub("sandbox", "production"))

    expect(response).to have_http_status(:ok)
    expect(partner.reload.argyle_environment).to eq("production")
    expect(partner.partner_application_attributes.count).to eq(2)
  end

  it "refuses a stale import with 409" do
    settings, = export_yaml
    import(settings_yaml: settings, expected_updated_at: "2000-01-01T00:00:00.000000Z")

    expect(response).to have_http_status(:conflict)
  end

  it "creates a new partner from both documents" do
    import(settings_yaml: admin_settings_document("imported").to_yaml, credentials_yaml: admin_credentials_document("imported").to_yaml,
           expected_updated_at: nil)

    expect(response).to have_http_status(:ok)
    expect(json_body).to include("exists" => false, "applied" => true, "partner_id" => "imported")
    expect(PartnerConfig.exists?(partner_id: "imported")).to be(true)
  end

  it "needs both documents for a new partner" do
    import(settings_yaml: admin_settings_document("imported").to_yaml, expected_updated_at: nil)

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "refuses invalid YAML" do
    import(settings_yaml: "partner_id: [unclosed")

    expect(response).to have_http_status(:unprocessable_content)
    expect(json_body["message"]).to include("Invalid YAML")
  end

  context "when settings are read-only (prod)" do
    let(:settings_writable) { false }

    it "refuses a settings document with 403" do
      settings, = export_yaml
      import(settings_yaml: settings, dry_run: true)

      expect(response).to have_http_status(:forbidden)
    end

    it "accepts a credentials document" do
      _, credentials = export_yaml
      import(credentials_yaml: credentials.sub("sandbox", "production"))

      expect(response).to have_http_status(:ok)
      expect(partner.reload.argyle_environment).to eq("production")
    end

    it "refuses creating a partner" do
      import(credentials_yaml: admin_credentials_document("imported").to_yaml, expected_updated_at: nil)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
