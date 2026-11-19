require "rails_helper"

# The loader features the admin API relies on.
RSpec.describe PartnerConfigLoader, type: :admin_api do
  let(:settings) { admin_settings_document }
  let(:credentials) { admin_credentials_document }

  def loader_for(s = settings, c = credentials)
    described_class.from_documents(s, c)
  end

  describe "reserved names and path_prefix" do
    it "reserves 'admin' as a domain and a partner_id" do
      expect(loader_for(settings.merge("domain" => "admin")).validate!.errors).to include(a_string_including("Invalid domain 'admin'"))
      expect(loader_for(settings.merge("partner_id" => "admin"), credentials.merge("partner_id" => "admin")).validate!.errors)
        .to include(a_string_including("Invalid partner_id 'admin'"))
    end

    it "rejects a leading slash in path_prefix for sftp and s3" do
      bad = credentials.deep_dup
      bad["transmission_methods"][0]["configs"][3]["value"] = "/inbox"

      expect(loader_for(settings, bad).validate!.error_details).to include(
        { message: "transmission_methods[0] (sftp): path_prefix must not start with '/'", path: "transmission_methods[0].configs[3]" }
      )
    end
  end

  it "reports a wrongly shaped section instead of raising" do
    loader = loader_for(settings.merge("application_attributes" => { "name" => "x" }, "translations" => [ "x" ])).validate!

    expect(loader.errors).to include("application_attributes must be a list", "translations must be a mapping")
  end

  it "gives every error a path where there is one" do
    loader = loader_for(settings.merge("pay_income_days_w2" => 30)).validate!

    expect(loader.error_details).to eq([ { message: "Invalid pay_income_days_w2 '30'. Valid: 90, 182", path: "pay_income_days_w2" } ])
    expect(loader.errors).to eq([ "Invalid pay_income_days_w2 '30'. Valid: 90, 182" ])
  end

  describe "keeping stored secrets" do
    let!(:partner) { create_admin_partner! }
    let(:masked) { admin_credentials_document(password: described_class::MASKED_PLACEHOLDER) }

    it "accepts $ENCRYPTED for a stored encrypted key and leaves the secret untouched on apply" do
      loader = loader_for(settings.merge("name" => "Renamed"), masked).keep_stored_secrets!(partner).validate!

      expect(loader).to be_valid
      loader.apply!
      expect(stored_secret("admin_spec", "sftp", "password").value).to eq("stored-sftp-password")
      expect(partner.reload.name).to eq("Renamed")
    end

    it "still rejects $ENCRYPTED without a stored secret" do
      expect(loader_for(settings, masked).validate!).not_to be_valid
      expect(loader_for(settings, masked).keep_stored_secrets!(nil).validate!).not_to be_valid
    end

    it "still rejects $ENCRYPTED for a key stored unencrypted" do
      url_masked = masked.deep_dup
      url_masked["transmission_methods"][0]["configs"][0]["value"] = described_class::MASKED_PLACEHOLDER

      expect(loader_for(settings, url_masked).keep_stored_secrets!(partner).validate!.errors)
        .to include(a_string_including("(url): value is the masked placeholder"))
    end
  end

  describe "#apply_settings!" do
    let!(:partner) { create_admin_partner! }

    it "applies settings and leaves credentials and ciphertext alone" do
      ciphertext = stored_secret("admin_spec", "sftp", "password")[:value]
      other_credentials = admin_credentials_document(password: "different").merge("argyle_environment" => "production")

      loader_for(settings.merge("name" => "Promoted"), other_credentials).validate!.apply_settings!

      expect(partner.reload.name).to eq("Promoted")
      expect(partner.argyle_environment).to eq("sandbox")
      expect(stored_secret("admin_spec", "sftp", "password")[:value]).to eq(ciphertext)
    end
  end

  describe "#apply_scoped!" do
    let!(:partner) { create_admin_partner! }

    it "writes only the named columns and sections, and touches the partner when only a section changed" do
      before = partner.updated_at
      changed = settings.merge("name" => "Not applied", "translations" => { "en" => settings["translations"]["en"] })

      travel 1.second do
        loader_for(changed).validate!.apply_scoped!(scalar_keys: [], sections: %i[translations])
      end

      partner.reload
      expect(partner.name).to eq("Admin Spec Agency")
      expect(partner.partner_translations.pluck(:locale).uniq).to eq(%w[en])
      expect(partner.updated_at).to be > before
    end
  end

  describe ".export" do
    before { create_admin_partner! }

    it "masks secrets unless asked for them" do
      password = ->(docs) { docs[:credentials]["transmission_methods"][0]["configs"].find { |c| c["key"] == "password" }["value"] }

      expect(password.call(described_class.export("admin_spec"))).to eq("$ENCRYPTED")
      expect(password.call(described_class.export("admin_spec", include_secrets: true))).to eq("stored-sftp-password")
    end
  end
end
