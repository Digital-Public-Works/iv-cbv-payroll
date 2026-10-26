require "rails_helper"

RSpec.describe "Admin API: editing partners", type: :request do
  let(:base) { "/api/admin/v1/partners/admin_spec" }
  let!(:partner) { create_admin_partner! }
  let(:settings_writable) { true }

  around { |example| with_admin_api(settings_writable: settings_writable) { example.run } }

  describe "POST …/validate" do
    it "validates a partial change merged onto the stored config" do
      admin_request(:post, "#{base}/validate", body: { settings: { pay_income_days_w2: 30 } })

      expect(response).to have_http_status(:ok)
      expect(json_body["valid"]).to be(false)
      expect(json_body["errors"]).to include({ "message" => "Invalid pay_income_days_w2 '30'. Valid: 90, 182", "path" => "pay_income_days_w2" })
    end

    it "accepts the stored config with masked secrets kept" do
      admin_request(:post, "#{base}/validate", body: {})

      expect(json_body).to include("valid" => true, "errors" => [])
    end

    it "reports error paths inside sections" do
      attrs = admin_settings_document["application_attributes"] + [ { "name" => "case_number" } ]
      admin_request(:post, "#{base}/validate", body: { settings: { application_attributes: attrs } })

      expect(json_body["errors"]).to include(a_hash_including("path" => "application_attributes[2].name"))
    end
  end

  describe "POST …/diff" do
    it "returns a field-level diff without writing" do
      admin_request(:post, "#{base}/diff", body: { settings: { name: "Renamed" }, credentials: { argyle_environment: "production" } })

      expect(response).to have_http_status(:ok)
      diff = json_body["diff"]
      expect(diff["settings"]["scalars"]).to eq([ { "key" => "name", "before" => "Admin Spec Agency", "after" => "Renamed" } ])
      expect(diff["credentials"]["scalars"]).to eq([ { "key" => "argyle_environment", "before" => "sandbox", "after" => "production" } ])
      expect(diff["deletes"]).to eq([])
      expect(partner.reload.name).to eq("Admin Spec Agency")
    end

    it "lists deletes and never includes secret values" do
      methods = [ { method_type: "shared_email", configs: [ { key: "email", value: "x@example.org", encrypted: false } ] } ]
      admin_request(:post, "#{base}/diff", body: { credentials: { transmission_methods: methods } })

      expect(json_body["diff"]["deletes"]).to include({ "section" => "transmission_methods", "name" => "sftp" })
      expect(response.body).not_to include("stored-sftp-password")
    end
  end

  describe "PATCH /api/admin/v1/partners/:partner_id" do
    def patch_partner(updated_at: admin_version("admin_spec"), **body)
      admin_request(:patch, base, body: body.merge(updated_at: updated_at))
    end

    it "updates only the supplied scalars and returns the new detail" do
      patch_partner(settings: { name: "Renamed" }, credentials: { weekly_report_recipients: "new@example.org" })

      expect(response).to have_http_status(:ok)
      expect(json_body["settings"]["name"]).to eq("Renamed")
      expect(json_body["credentials"]["weekly_report_recipients"]).to eq("new@example.org")
      expect(json_body["updated_at"]).not_to eq(AdminApi::PartnerDocuments.version(partner))
      partner.reload
      expect(partner.timezone).to eq("America/New_York")
      expect(partner.partner_application_attributes.count).to eq(2)
      expect(stored_secret("admin_spec", "sftp", "password").value).to eq("stored-sftp-password")
    end

    it "leaves columns the loader doesn't know about untouched" do
      partner.update_columns(created_at: 3.days.ago.round)
      created_at = partner.reload.created_at

      patch_partner(settings: { name: "Renamed" })

      expect(partner.reload.created_at).to eq(created_at)
    end

    it "replaces a whole settings section, and moves the version token" do
      before = admin_version("admin_spec")
      patch_partner(settings: { translations: { "en" => { "shared.agency_full_name" => "Only English" } } })

      expect(response).to have_http_status(:ok)
      expect(partner.reload.partner_translations.pluck(:locale, :key, :value)).to eq([ [ "en", "shared.agency_full_name", "Only English" ] ])
      expect(admin_version("admin_spec")).not_to eq(before)
    end

    it "replaces attribute-usage lists in the given order" do
      patch_partner(settings: { applicant_input_page: [ { name: "case_number", required: false }, { name: "first_name", required: true } ] })

      expect(json_body["settings"]["applicant_input_page"]).to eq([ { "name" => "case_number", "required" => false }, { "name" => "first_name", "required" => true } ])
    end

    it "refuses a stale write with 409" do
      stale = admin_version("admin_spec")
      patch_partner(settings: { name: "First" }, updated_at: stale)
      patch_partner(settings: { name: "Second" }, updated_at: stale)

      expect(response).to have_http_status(:conflict)
      expect(partner.reload.name).to eq("First")
    end

    it "refuses an invalid change with 422 and field paths, writing nothing" do
      patch_partner(settings: { pay_income_days_w2: 30, name: "Renamed" })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_body["errors"]).to include(a_hash_including("path" => "pay_income_days_w2"))
      expect(partner.reload.name).to eq("Admin Spec Agency")
    end

    it "refuses a reserved domain" do
      patch_partner(settings: { domain: "admin" })

      expect(json_body["errors"]).to include(a_hash_including("path" => "domain"))
    end

    it "refuses changing partner_id" do
      patch_partner(settings: { partner_id: "other" })

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "sends transmission methods to PUT …/transmission_methods" do
      patch_partner(credentials: { transmission_methods: [] })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_body["message"]).to include("transmission_methods")
    end

    it "refuses a body that isn't a JSON object" do
      admin_request(:patch, base, body: [ 1, 2 ])

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "logs the change with key names only" do
      allow(Rails.logger).to receive(:info).and_call_original

      patch_partner(settings: { name: "A secret-looking name" })

      expect(Rails.logger).to have_received(:info).with(a_string_including("action=update", "partner=admin_spec", "changed=name", "result=ok", "actor=operator@"))
      expect(Rails.logger).not_to have_received(:info).with(a_string_including("admin_api", "A secret-looking name"))
    end

    context "when settings are read-only (prod)" do
      let(:settings_writable) { false }

      it "refuses settings with 403" do
        patch_partner(settings: { name: "Renamed" })

        expect(response).to have_http_status(:forbidden)
        expect(partner.reload.name).to eq("Admin Spec Agency")
      end

      it "allows credentials" do
        patch_partner(credentials: { argyle_environment: "production" })

        expect(response).to have_http_status(:ok)
        expect(partner.reload.argyle_environment).to eq("production")
      end

      it "logs the refusal" do
        allow(Rails.logger).to receive(:info).and_call_original

        patch_partner(settings: { name: "Renamed" })

        expect(Rails.logger).to have_received(:info).with(a_string_including("action=update", "result=403"))
      end
    end
  end

  describe "PUT …/transmission_methods" do
    def methods_with(password:, url: "sftp.example.org", extra: [])
      [
        {
          method_type: "sftp",
          configs: [
            { key: "url", value: url, encrypted: false },
            { key: "user", value: "agency", encrypted: false },
            { key: "password", value: password, encrypted: true },
            { key: "path_prefix", value: "inbox", encrypted: false }
          ]
        }
      ] + extra
    end

    def put_methods(methods, updated_at: admin_version("admin_spec"))
      admin_request(:put, "#{base}/transmission_methods", body: { updated_at: updated_at, transmission_methods: methods })
    end

    it "keeps a stored secret sent as $ENCRYPTED" do
      put_methods(methods_with(password: "$ENCRYPTED", url: "sftp2.example.org"))

      expect(response).to have_http_status(:ok)
      expect(stored_secret("admin_spec", "sftp", "url").value).to eq("sftp2.example.org")
      expect(stored_secret("admin_spec", "sftp", "password").value).to eq("stored-sftp-password")
      expect(response.body).not_to include("stored-sftp-password")
    end

    it "replaces a secret given a new value, encrypted" do
      put_methods(methods_with(password: "rotated"))

      config = stored_secret("admin_spec", "sftp", "password")
      expect(config.value).to eq("rotated")
      expect(config.is_encrypted).to be(true)
      expect(config[:value]).not_to eq("rotated")
    end

    it "adds and removes methods" do
      email = { method_type: "shared_email", configs: [ { key: "email", value: "reports@example.org", encrypted: false } ] }
      put_methods(methods_with(password: "$ENCRYPTED", extra: [ email ]))
      expect(partner.reload.partner_transmission_methods.map(&:method_type)).to match_array(%w[sftp shared_email])

      put_methods([ email ])
      expect(partner.reload.partner_transmission_methods.map(&:method_type)).to eq(%w[shared_email])
    end

    it "refuses $ENCRYPTED for a secret that isn't stored" do
      email = { method_type: "webhook", configs: [ { key: "webhook_url", value: "https://example.org/hook", encrypted: false },
                                                   { key: "api_key", value: "$ENCRYPTED", encrypted: true } ] }
      put_methods(methods_with(password: "$ENCRYPTED", extra: [ email ]))

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_body["errors"]).to include(a_hash_including("path" => "transmission_methods[1].configs[1]"))
    end

    it "refuses a leading slash in path_prefix" do
      methods = methods_with(password: "$ENCRYPTED")
      methods[0][:configs][3][:value] = "/inbox"
      put_methods(methods)

      expect(json_body["errors"]).to include(a_hash_including("message" => a_string_including("path_prefix must not start with '/'")))
    end

    it "is allowed where settings are read-only (prod)" do
      stub_environment_variable("ADMIN_API_SETTINGS_WRITABLE", nil) do
        put_methods(methods_with(password: "$ENCRYPTED", url: "sftp3.example.org"))
      end

      expect(response).to have_http_status(:ok)
    end

    it "refuses a stale write with 409" do
      put_methods(methods_with(password: "$ENCRYPTED"), updated_at: "2000-01-01T00:00:00.000000Z")

      expect(response).to have_http_status(:conflict)
    end
  end

  describe "POST /api/admin/v1/partners" do
    let(:new_settings) { admin_settings_document("brand_new") }
    let(:new_credentials) { admin_credentials_document("brand_new") }

    it "creates a valid partner" do
      admin_request(:post, "/api/admin/v1/partners", body: { settings: new_settings, credentials: new_credentials })

      expect(response).to have_http_status(:ok)
      expect(json_body["partner_id"]).to eq("brand_new")
      expect(stored_secret("brand_new", "sftp", "password").value).to eq("stored-sftp-password")
    end

    it "refuses the reserved partner_id 'admin'" do
      admin_request(:post, "/api/admin/v1/partners", body: { settings: admin_settings_document("admin").merge("domain" => "admin-x"),
                                                            credentials: admin_credentials_document("admin") })

      expect(json_body["errors"]).to include(a_hash_including("path" => "partner_id"))
    end

    it "refuses an existing partner_id with 409" do
      admin_request(:post, "/api/admin/v1/partners", body: { settings: admin_settings_document, credentials: admin_credentials_document })

      expect(response).to have_http_status(:conflict)
    end

    context "when settings are read-only (prod)" do
      let(:settings_writable) { false }

      it "refuses with 403" do
        admin_request(:post, "/api/admin/v1/partners", body: { settings: new_settings, credentials: new_credentials })

        expect(response).to have_http_status(:forbidden)
        expect(PartnerConfig.exists?(partner_id: "brand_new")).to be(false)
      end
    end
  end
end
