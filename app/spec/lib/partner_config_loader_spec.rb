require "rails_helper"
require "partner_config_loader"

RSpec.describe PartnerConfigLoader do
  # A single combined config, split into settings + credentials documents by the
  # #write_sources helper below. Keeps individual tests readable — they mutate
  # `valid_yaml` and hand the whole thing to the loader, which sees two files.
  let(:valid_yaml) do
    {
      "partner_id" => "test_partner",
      "name" => "Test Agency",
      "state_name" => "Testonia",
      "timezone" => "America/New_York",
      "domain" => "test",
      "website" => "https://test.example.com",
      "logo_path" => "test_logo.svg",
      "argyle_environment" => "sandbox",
      "active_demo" => true,
      "active_prod" => false,
      "pilot_ended" => false,
      "staff_portal_enabled" => false,
      "generic_links_enabled" => true,
      "invitation_links_enabled" => true,
      "invitation_valid_days_default" => 10,
      "pay_income_days_w2" => 90,
      "pay_income_days_gig" => 182,
      "report_customization_show_earnings_list" => true,
      "weekly_report_enabled" => false,
      "partner_identifier_name" => "case_number",
      "transmission_methods" => [
        {
          "method_type" => "shared_email",
          "configs" => [
            { "key" => "email", "encrypted" => false, "value" => "reports@test.example.com" }
          ]
        }
      ],
      "application_attributes" => [
        {
          "name" => "case_number",
          "required" => true,
          "data_type" => "string",
          "form_field_type" => "text_field",
          "show_on_applicant_form" => false,
          "show_on_caseworker_form" => true,
          "show_on_caseworker_report" => true,
          "redactable" => false
        },
        {
          "name" => "first_name",
          "required" => true,
          "data_type" => "string",
          "form_field_type" => "text_field",
          "redactable" => true,
          "redact_type" => "string"
        }
      ],
      "translations" => {
        "en" => {
          "shared.agency_acronym" => "TEST",
          "shared.agency_full_name" => "Test Agency",
          "shared.header.cbv_flow_title" => "Verify your income",
          "shared.header.preheader" => "Test Income Verification"
        },
        "es" => {
          "shared.agency_acronym" => "TEST",
          "shared.agency_full_name" => "Agencia de Prueba",
          "shared.header.cbv_flow_title" => "Verifique sus ingresos",
          "shared.header.preheader" => "Verificacion de ingresos"
        }
      }
    }
  end

  before { @tempfiles = [] }
  after { @tempfiles.each { |f| f.close! if f.respond_to?(:close!) } }

  # Partition a combined hash into settings + credentials documents and write
  # both to temp files, returning [settings_path, credentials_path]. Credential
  # keys go to the credentials file; everything else (including unknown keys) to
  # the settings file, so the partition validator can flag typos.
  def write_sources(combined)
    cred_keys = described_class::CREDENTIAL_TOP_LEVEL
    credentials = combined.slice(*cred_keys)
    credentials["partner_id"] ||= combined["partner_id"]
    settings = combined.except(*(cred_keys - [ "partner_id" ]))
    write_pair(settings, credentials)
  end

  def write_pair(settings, credentials)
    s = Tempfile.new([ "settings", ".yml" ])
    s.write(settings.to_yaml)
    s.rewind
    c = Tempfile.new([ "credentials", ".yml" ])
    c.write(credentials.to_yaml)
    c.rewind
    @tempfiles.push(s, c)
    [ s.path, c.path ]
  end

  def loader_for(combined)
    described_class.new(*write_sources(combined))
  end

  describe "#load!" do
    it "loads and merges the two documents" do
      loader = loader_for(valid_yaml)
      loader.load!
      expect(loader.yaml_data[:partner_id]).to eq("test_partner")
      expect(loader.yaml_data[:name]).to eq("Test Agency")               # from settings
      expect(loader.yaml_data[:argyle_environment]).to eq("sandbox")     # from credentials
      expect(loader.yaml_data[:transmission_methods].size).to eq(1)      # from credentials
    end

    it "raises SourceError for a missing file" do
      loader = described_class.new("/nonexistent/settings.yml", "/nonexistent/credentials.yml")
      expect { loader.load! }.to raise_error(PartnerConfigLoader::SourceError, /File not found/)
    end

    it "raises SourceError for invalid YAML" do
      bad = Tempfile.new([ "bad", ".yml" ])
      bad.write("{ invalid yaml: [")
      bad.rewind
      @tempfiles << bad
      _settings, credentials = write_sources(valid_yaml)

      loader = described_class.new(bad.path, credentials)
      expect { loader.load! }.to raise_error(PartnerConfigLoader::SourceError, /Invalid YAML/)
    end
  end

  describe "#validate!" do
    it "passes for a valid config" do
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      expect(loader.valid?).to be true
      expect(loader.errors).to be_empty
      expect(loader.warnings).to be_empty
    end

    it "errors on missing required attributes" do
      valid_yaml.delete("name")
      valid_yaml.delete("timezone")
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      expect(loader.valid?).to be false
      expect(loader.errors).to include(/Missing required attribute: name/)
      expect(loader.errors).to include(/Missing required attribute: timezone/)
    end

    it "errors on invalid transmission method_type" do
      valid_yaml["transmission_methods"] = [ { "method_type" => "vibes", "configs" => [] } ]
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      expect(loader.valid?).to be false
      expect(loader.errors).to include(/invalid method_type/)
    end

    it "errors when no transmission methods are configured" do
      valid_yaml.delete("transmission_methods")
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      expect(loader.valid?).to be false
      expect(loader.errors).to include(/At least one transmission method is required/)
    end

    it "errors on an unknown top-level key" do
      valid_yaml["include_paystubz"] = true # typo
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      expect(loader.valid?).to be false
      expect(loader.errors).to include(/unknown top-level key 'include_paystubz'/)
    end

    it "rejects the singular transmission_method / top-level transmission_configs format" do
      valid_yaml.delete("transmission_methods")
      valid_yaml["transmission_method"] = "unencrypted_s3"
      valid_yaml["transmission_configs"] = [ { "key" => "bucket", "value" => "b" } ]
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      expect(loader.valid?).to be false
      expect(loader.errors).to include(/unknown top-level key 'transmission_configs'/)
      expect(loader.errors).to include(/Use 'transmission_methods' \(plural\)/)
    end

    it "errors on an unknown key within a transmission config" do
      valid_yaml["transmission_methods"][0]["configs"][0]["pat_prefix"] = "oops" # typo
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      expect(loader.valid?).to be false
      expect(loader.errors).to include(/transmission_methods\[0\]\.configs\[0\]: unknown key 'pat_prefix'/)
    end

    it "errors on an unknown key within an application attribute" do
      valid_yaml["application_attributes"][0]["requried"] = true # typo
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      expect(loader.valid?).to be false
      expect(loader.errors).to include(/application_attributes\[0\]: unknown key 'requried'/)
    end

    it "accepts a path_prefix transmission config key" do
      valid_yaml["transmission_methods"][0]["configs"] << { "key" => "path_prefix", "encrypted" => false, "value" => "outout" }
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      expect(loader.valid?).to be true
    end

    it "errors on invalid pay_income_days" do
      valid_yaml["pay_income_days_w2"] = 45
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      expect(loader.valid?).to be false
      expect(loader.errors).to include(/Invalid pay_income_days_w2/)
    end

    it "errors on reserved domain prefix" do
      valid_yaml["domain"] = "static"
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      expect(loader.valid?).to be false
      expect(loader.errors).to include(/Invalid domain 'static'/)
    end

    it "errors on invalid application attribute data_type" do
      valid_yaml["application_attributes"][0]["data_type"] = "EBCDIC"
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      expect(loader.valid?).to be false
      expect(loader.errors).to include(/invalid data_type/)
    end

    it "errors on duplicate application attribute names" do
      valid_yaml["application_attributes"] << valid_yaml["application_attributes"][0].dup
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      expect(loader.valid?).to be false
      expect(loader.errors).to include(/duplicate name 'case_number'/)
    end

    it "warns on missing recommended translations" do
      valid_yaml["translations"]["en"].delete("shared.agency_full_name")
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      expect(loader.valid?).to be true
      expect(loader.warnings).to include(/Missing recommended translation.*en.*shared\.agency_full_name/)
    end

    it "does not warn when the optional agency_acronym translation is absent" do
      valid_yaml["translations"]["en"].delete("shared.agency_acronym")
      valid_yaml["translations"]["es"].delete("shared.agency_acronym")
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      expect(loader.valid?).to be true
      expect(loader.warnings).not_to include(/shared\.agency_acronym/)
    end

    context "settings/credentials partition" do
      it "errors when a credential key appears in the settings file" do
        settings = valid_yaml.except("transmission_methods")
        settings["argyle_environment"] = "sandbox" # credential key in the wrong file
        credentials = { "partner_id" => "test_partner", "argyle_environment" => "sandbox",
                        "transmission_methods" => valid_yaml["transmission_methods"] }
        loader = described_class.new(*write_pair(settings, credentials))
        loader.load!
        loader.validate!
        expect(loader.valid?).to be false
        expect(loader.errors).to include(/Settings file contains credential key 'argyle_environment'/)
      end

      it "errors when a settings key appears in the credentials file" do
        settings = valid_yaml.except("argyle_environment", "transmission_methods")
        credentials = { "partner_id" => "test_partner", "argyle_environment" => "sandbox",
                        "timezone" => "America/New_York", # settings key in the wrong file
                        "transmission_methods" => valid_yaml["transmission_methods"] }
        loader = described_class.new(*write_pair(settings, credentials))
        loader.load!
        loader.validate!
        expect(loader.valid?).to be false
        expect(loader.errors).to include(/Credentials file contains settings key 'timezone'/)
      end

      it "errors when partner_id differs between the two files" do
        settings = valid_yaml.except("argyle_environment", "transmission_methods")
        credentials = { "partner_id" => "other_partner", "argyle_environment" => "sandbox",
                        "transmission_methods" => valid_yaml["transmission_methods"] }
        loader = described_class.new(*write_pair(settings, credentials))
        loader.load!
        loader.validate!
        expect(loader.valid?).to be false
        expect(loader.errors).to include(/partner_id mismatch/)
      end
    end

    context "credential requirements" do
      it "errors when argyle_environment is missing" do
        valid_yaml.delete("argyle_environment")
        loader = loader_for(valid_yaml)
        loader.load!
        loader.validate!
        expect(loader.errors).to include(/Missing required credential: argyle_environment/)
      end

      it "errors when argyle_environment is invalid" do
        valid_yaml["argyle_environment"] = "staging"
        loader = loader_for(valid_yaml)
        loader.load!
        loader.validate!
        expect(loader.errors).to include(/Invalid argyle_environment 'staging'/)
      end

      it "errors when a required transmission credential key is missing" do
        valid_yaml["transmission_methods"] = [
          { "method_type" => "sftp", "configs" => [
            { "key" => "url", "value" => "sftp.example.com" },
            { "key" => "user", "value" => "u" },
            { "key" => "path_prefix", "value" => "" }
            # password missing
          ] }
        ]
        loader = loader_for(valid_yaml)
        loader.load!
        loader.validate!
        expect(loader.valid?).to be false
        expect(loader.errors).to include(/sftp\): missing required credential 'password'/)
      end

      it "errors when a required transmission credential value is blank" do
        valid_yaml["transmission_methods"] = [
          { "method_type" => "sftp", "configs" => [
            { "key" => "url", "value" => "" }, # blank not allowed for url
            { "key" => "user", "value" => "u" },
            { "key" => "password", "value" => "p" },
            { "key" => "path_prefix", "value" => "" } # blank allowed for path_prefix
          ] }
        ]
        loader = loader_for(valid_yaml)
        loader.load!
        loader.validate!
        expect(loader.valid?).to be false
        expect(loader.errors).to include(/sftp\): credential 'url' must not be blank/)
        expect(loader.errors).not_to include(/path_prefix/)
      end

      it "rejects a masked $ENCRYPTED placeholder value" do
        valid_yaml["transmission_methods"] = [
          { "method_type" => "webhook", "configs" => [
            { "key" => "webhook_url", "value" => "https://example.com/hook" },
            { "key" => "api_key", "encrypted" => true, "value" => "$ENCRYPTED" }
          ] }
        ]
        loader = loader_for(valid_yaml)
        loader.load!
        loader.validate!
        expect(loader.valid?).to be false
        expect(loader.errors).to include(/masked placeholder \$ENCRYPTED/)
      end
    end
  end

  describe "#apply!" do
    it "creates a new partner config from the merged documents" do
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!

      expect { loader.apply! }.to change(PartnerConfig, :count).by(1)

      pc = PartnerConfig.find_by(partner_id: "test_partner")
      expect(pc.name).to eq("Test Agency")
      expect(pc.timezone).to eq("America/New_York")
      expect(pc.argyle_environment).to eq("sandbox")
      expect(pc.pay_income_days_w2).to eq(90)
      expect(pc.pay_income_days_gig).to eq(182)
    end

    it "applies include_paystubs" do
      valid_yaml["include_paystubs"] = true
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      loader.apply!
      expect(PartnerConfig.find_by(partner_id: "test_partner").include_paystubs).to be true
    end

    it "creates transmission methods and their configs" do
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      loader.apply!

      pc = PartnerConfig.find_by(partner_id: "test_partner")
      ptm = pc.partner_transmission_methods.first
      expect(ptm.method_type).to eq("shared_email")
      tc = ptm.partner_transmission_configs.first
      expect(tc.key).to eq("email")
      expect(tc.value).to eq("reports@test.example.com")
    end

    it "stores transmission config values literally (no env-var substitution)" do
      valid_yaml["transmission_methods"] = [
        { "method_type" => "shared_email", "configs" => [
          { "key" => "email", "encrypted" => false, "value" => "$LITERAL_NOT_AN_ENV_VAR" }
        ] }
      ]
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      loader.apply!

      pc = PartnerConfig.find_by(partner_id: "test_partner")
      tc = pc.partner_transmission_methods.first.partner_transmission_configs.find_by(key: "email")
      expect(tc.value).to eq("$LITERAL_NOT_AN_ENV_VAR")
    end

    it "creates application attributes" do
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      loader.apply!

      pc = PartnerConfig.find_by(partner_id: "test_partner")
      expect(pc.partner_application_attributes.count).to eq(2)
      case_attr = pc.partner_application_attributes.find_by(name: "case_number")
      expect(case_attr.required).to be true
      expect(case_attr.show_on_caseworker_report).to be true
    end

    it "creates translations" do
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      loader.apply!

      pc = PartnerConfig.find_by(partner_id: "test_partner")
      expect(pc.partner_translations.where(locale: "en").count).to eq(4)
      expect(pc.partner_translations.where(locale: "es").count).to eq(4)
    end

    it "updates an existing partner config" do
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      loader.apply!

      valid_yaml["name"] = "Updated Agency"
      loader2 = loader_for(valid_yaml)
      loader2.load!
      loader2.validate!
      changes = loader2.apply!

      expect(changes[:config]).to eq(:updated)
      expect(PartnerConfig.find_by(partner_id: "test_partner").name).to eq("Updated Agency")
    end

    it "removes application attributes not in the merged config" do
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      loader.apply!

      pc = PartnerConfig.find_by(partner_id: "test_partner")
      expect(pc.partner_application_attributes.count).to eq(2)

      valid_yaml["application_attributes"] = [ valid_yaml["application_attributes"][0] ]
      loader2 = loader_for(valid_yaml)
      loader2.load!
      loader2.validate!
      changes = loader2.apply!

      expect(changes[:application_attributes][:deleted]).to eq(1)
      expect(pc.reload.partner_application_attributes.count).to eq(1)
    end

    it "returns a change summary" do
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      changes = loader.apply!

      expect(changes[:config]).to eq(:created)
      expect(changes[:transmission_methods][:created]).to eq(2) # 1 method + 1 config
      expect(changes[:application_attributes][:created]).to eq(2)
      expect(changes[:translations][:created]).to eq(8)
    end
  end

  describe ".export" do
    before do
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      loader.apply!
    end

    it "splits the DB config into settings and credentials documents" do
      data = described_class.export("test_partner")

      # partner_id appears in both as the pairing cross-check
      expect(data[:settings]["partner_id"]).to eq("test_partner")
      expect(data[:credentials]["partner_id"]).to eq("test_partner")

      # shared config -> settings
      expect(data[:settings]["name"]).to eq("Test Agency")
      expect(data[:settings]).not_to have_key("argyle_environment")
      expect(data[:settings]).not_to have_key("transmission_methods")

      # env-specific config -> credentials
      expect(data[:credentials]["argyle_environment"]).to eq("sandbox")
      expect(data[:credentials]["transmission_methods"][0]["method_type"]).to eq("shared_email")
      expect(data[:credentials]).not_to have_key("name")
    end

    it "exports application attributes and translations under settings" do
      data = described_class.export("test_partner")
      names = data[:settings]["application_attributes"].map { |a| a["name"] }
      expect(names).to contain_exactly("case_number", "first_name")
      expect(data[:settings]["translations"]["en"]["shared.agency_acronym"]).to eq("TEST")
    end

    it "masks encrypted transmission config values in the credentials document" do
      valid_yaml["transmission_methods"] = [
        { "method_type" => "shared_email", "configs" => [
          { "key" => "email", "encrypted" => false, "value" => "reports@test.example.com" },
          { "key" => "secret", "encrypted" => true, "value" => "plaintext_for_test" }
        ] }
      ]
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      loader.apply!

      data = described_class.export("test_partner")
      secret = data[:credentials]["transmission_methods"][0]["configs"].find { |c| c["key"] == "secret" }
      expect(secret["value"]).to eq("$ENCRYPTED")
    end

    it "raises for an unknown partner" do
      expect { described_class.export("nonexistent") }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "output configuration fields" do
    it "applies the flat include_full_ssn and include_direct_deposit_last_4 flags" do
      valid_yaml["include_full_ssn"] = true
      valid_yaml["include_direct_deposit_last_4"] = true
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      loader.apply!

      partner_config = PartnerConfig.find_by(partner_id: "test_partner")
      expect(partner_config.include_full_ssn).to be(true)
      expect(partner_config.include_direct_deposit_last_4).to be(true)
    end

    it "defaults the flags to false when omitted" do
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      loader.apply!

      partner_config = PartnerConfig.find_by(partner_id: "test_partner")
      expect(partner_config.include_full_ssn).to be(false)
      expect(partner_config.include_direct_deposit_last_4).to be(false)
    end

    it "exports the flat flags under settings" do
      valid_yaml["include_full_ssn"] = true
      valid_yaml["include_direct_deposit_last_4"] = false
      loader = loader_for(valid_yaml)
      loader.load!
      loader.validate!
      loader.apply!

      data = described_class.export("test_partner")
      expect(data[:settings]["include_full_ssn"]).to be(true)
      expect(data[:settings]["include_direct_deposit_last_4"]).to be(false)
    end
  end
end
