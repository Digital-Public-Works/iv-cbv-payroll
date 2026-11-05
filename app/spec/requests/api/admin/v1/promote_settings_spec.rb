require "rails_helper"

RSpec.describe "Admin API: promote settings", type: :request do
  let(:settings_writable) { false }
  let(:demo_settings) { admin_settings_document.merge("name" => "Renamed in demo", "active_prod" => true) }

  around { |example| with_admin_api(settings_writable: settings_writable) { example.run } }

  def promote(partner_id: "admin_spec", settings: demo_settings, credentials: nil, expected: nil)
    admin_request(:post, "/api/admin/v1/partners/#{partner_id}/promote_settings",
                  body: { settings: settings, source_fingerprint: "abc123", expected_prod_updated_at: expected, credentials: credentials })
  end

  context "with an existing partner" do
    let!(:partner) { create_admin_partner!(credentials: admin_credentials_document(password: "prod-password").merge("argyle_environment" => "production")) }

    it "applies demo's settings now and leaves prod credentials untouched" do
      promote(expected: admin_version("admin_spec"))

      expect(response).to have_http_status(:ok)
      partner.reload
      expect(partner.name).to eq("Renamed in demo")
      expect(partner.active_prod).to be(true)
      expect(partner.argyle_environment).to eq("production")
      expect(stored_secret("admin_spec", "sftp", "password").value).to eq("prod-password")
      expect(response.body).not_to include("prod-password")
    end

    it "ignores credentials sent for an existing partner" do
      promote(expected: admin_version("admin_spec"), credentials: admin_credentials_document(password: "from-demo"))

      expect(stored_secret("admin_spec", "sftp", "password").value).to eq("prod-password")
    end

    it "refuses when prod changed since the diff was shown (409)" do
      promote(expected: "2000-01-01T00:00:00.000000Z")

      expect(response).to have_http_status(:conflict)
      expect(partner.reload.name).to eq("Admin Spec Agency")
    end

    it "refuses invalid settings with 422" do
      promote(settings: demo_settings.merge("pay_income_days_w2" => 30), expected: admin_version("admin_spec"))

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses settings for a different partner" do
      promote(settings: demo_settings.merge("partner_id" => "other"), expected: admin_version("admin_spec"))

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "logs the promotion with its source fingerprint" do
      allow(Rails.logger).to receive(:info).and_call_original

      promote(expected: admin_version("admin_spec"))

      expect(Rails.logger).to have_received(:info).with(a_string_including("action=promote_settings", "source_fingerprint=abc123", "result=ok"))
    end
  end

  context "with a partner new to prod" do
    it "creates it with the prod credentials supplied" do
      promote(partner_id: "brand_new", settings: admin_settings_document("brand_new"), credentials: admin_credentials_document("brand_new"))

      expect(response).to have_http_status(:ok)
      expect(PartnerConfig.find_by!(partner_id: "brand_new").name).to eq("Admin Spec Agency")
    end

    it "requires credentials" do
      promote(partner_id: "brand_new", settings: admin_settings_document("brand_new"))

      expect(response).to have_http_status(:unprocessable_content)
      expect(PartnerConfig.exists?(partner_id: "brand_new")).to be(false)
    end

    it "refuses masked secrets, since there is nothing stored to keep" do
      promote(partner_id: "brand_new", settings: admin_settings_document("brand_new"),
              credentials: admin_credentials_document("brand_new", password: "$ENCRYPTED"))

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  context "where settings are writable (demo)" do
    let(:settings_writable) { true }

    it "doesn't exist" do
      create_admin_partner!
      promote(expected: admin_version("admin_spec"))

      expect(response).to have_http_status(:not_found)
    end
  end
end
