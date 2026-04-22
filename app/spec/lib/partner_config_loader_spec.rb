require "rails_helper"
require "partner_config_loader"

RSpec.describe PartnerConfigLoader do
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
      "transmission_method" => "shared_email",
      "transmission_configs" => [
        { "key" => "email", "encrypted" => false, "value" => "reports@test.example.com" }
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
          "shared.header.preheader" => "Test Income Verification",
          "shared.benefit" => "benefits",
          "shared.reporting_purpose" => "benefits eligibility"
        },
        "es" => {
          "shared.agency_acronym" => "TEST",
          "shared.agency_full_name" => "Agencia de Prueba",
          "shared.header.cbv_flow_title" => "Verifique sus ingresos",
          "shared.header.preheader" => "Verificacion de ingresos",
          "shared.benefit" => "beneficios",
          "shared.reporting_purpose" => "elegibilidad de beneficios"
        }
      }
    }
  end

  let(:yaml_file) do
    file = Tempfile.new([ "partner_config", ".yml" ])
    file.write(valid_yaml.to_yaml)
    file.rewind
    file
  end

  after { yaml_file.close! if yaml_file.respond_to?(:close!) }

  describe "#load!" do
    it "loads YAML from a file path" do
      loader = described_class.new(yaml_file.path)
      loader.load!
      expect(loader.data[:partner_id]).to eq("test_partner")
    end

    it "raises SourceError for missing file" do
      loader = described_class.new("/nonexistent/path.yml")
      expect { loader.load! }.to raise_error(PartnerConfigLoader::SourceError, /File not found/)
    end

    it "raises SourceError for invalid YAML" do
      bad_file = Tempfile.new([ "bad", ".yml" ])
      bad_file.write("{ invalid yaml: [")
      bad_file.rewind

      loader = described_class.new(bad_file.path)
      expect { loader.load! }.to raise_error(PartnerConfigLoader::SourceError, /Invalid YAML/)
    ensure
      bad_file.close!
    end
  end

  describe "#validate!" do
    it "passes for valid config" do
      loader = described_class.new(yaml_file.path)
      loader.load!
      loader.validate!
      expect(loader.valid?).to be true
      expect(loader.errors).to be_empty
      expect(loader.warnings).to be_empty
    end

    it "errors on missing required attributes" do
      valid_yaml.delete("name")
      valid_yaml.delete("timezone")
      yaml_file.reopen(yaml_file.path, "w")
      yaml_file.write(valid_yaml.to_yaml)
      yaml_file.rewind

      loader = described_class.new(yaml_file.path)
      loader.load!
      loader.validate!
      expect(loader.valid?).to be false
      expect(loader.errors).to include(/Missing required attribute: name/)
      expect(loader.errors).to include(/Missing required attribute: timezone/)
    end

    it "errors on invalid transmission_method" do
      valid_yaml["transmission_method"] = "vibes"
      yaml_file.reopen(yaml_file.path, "w")
      yaml_file.write(valid_yaml.to_yaml)
      yaml_file.rewind

      loader = described_class.new(yaml_file.path)
      loader.load!
      loader.validate!
      expect(loader.valid?).to be false
      expect(loader.errors).to include(/Invalid transmission_method/)
    end

    it "errors on invalid pay_income_days" do
      valid_yaml["pay_income_days_w2"] = 45
      yaml_file.reopen(yaml_file.path, "w")
      yaml_file.write(valid_yaml.to_yaml)
      yaml_file.rewind

      loader = described_class.new(yaml_file.path)
      loader.load!
      loader.validate!
      expect(loader.valid?).to be false
      expect(loader.errors).to include(/Invalid pay_income_days_w2/)
    end

    it "errors on invalid application attribute data_type" do
      valid_yaml["application_attributes"][0]["data_type"] = "EBCDIC"
      yaml_file.reopen(yaml_file.path, "w")
      yaml_file.write(valid_yaml.to_yaml)
      yaml_file.rewind

      loader = described_class.new(yaml_file.path)
      loader.load!
      loader.validate!
      expect(loader.valid?).to be false
      expect(loader.errors).to include(/invalid data_type/)
    end

    it "errors on duplicate application attribute names" do
      valid_yaml["application_attributes"] << valid_yaml["application_attributes"][0].dup
      yaml_file.reopen(yaml_file.path, "w")
      yaml_file.write(valid_yaml.to_yaml)
      yaml_file.rewind

      loader = described_class.new(yaml_file.path)
      loader.load!
      loader.validate!
      expect(loader.valid?).to be false
      expect(loader.errors).to include(/duplicate name 'case_number'/)
    end

    it "warns on missing recommended translations" do
      valid_yaml["translations"]["en"].delete("shared.benefit")
      yaml_file.reopen(yaml_file.path, "w")
      yaml_file.write(valid_yaml.to_yaml)
      yaml_file.rewind

      loader = described_class.new(yaml_file.path)
      loader.load!
      loader.validate!
      expect(loader.valid?).to be true
      expect(loader.warnings).to include(/Missing recommended translation.*en.*shared\.benefit/)
    end

    context "with $ENV_VAR references" do
      before do
        valid_yaml["transmission_configs"] = [
          { "key" => "user", "encrypted" => true, "value" => "$TEST_SFTP_USER" }
        ]
        yaml_file.reopen(yaml_file.path, "w")
        yaml_file.write(valid_yaml.to_yaml)
        yaml_file.rewind
      end

      it "warns when env var is not set" do
        loader = described_class.new(yaml_file.path)
        loader.load!
        loader.validate!
        expect(loader.warnings).to include(/TEST_SFTP_USER.*is not set/)
      end

      it "does not warn when env var is set" do
        ClimateControl.modify(TEST_SFTP_USER: "testuser") do
          loader = described_class.new(yaml_file.path)
          loader.load!
          loader.validate!
          expect(loader.warnings.select { |w| w.include?("TEST_SFTP_USER") }).to be_empty
        end
      end
    end
  end

  describe "#apply!" do
    it "creates a new partner config" do
      loader = described_class.new(yaml_file.path)
      loader.load!
      loader.validate!

      expect { loader.apply! }.to change(PartnerConfig, :count).by(1)

      pc = PartnerConfig.find_by(partner_id: "test_partner")
      expect(pc.name).to eq("Test Agency")
      expect(pc.timezone).to eq("America/New_York")
      expect(pc.transmission_method).to eq("shared_email")
      expect(pc.pay_income_days_w2).to eq(90)
      expect(pc.pay_income_days_gig).to eq(182)
    end

    it "creates transmission configs" do
      loader = described_class.new(yaml_file.path)
      loader.load!
      loader.validate!
      loader.apply!

      pc = PartnerConfig.find_by(partner_id: "test_partner")
      expect(pc.partner_transmission_configs.count).to eq(1)
      tc = pc.partner_transmission_configs.first
      expect(tc.key).to eq("email")
      expect(tc.value).to eq("reports@test.example.com")
    end

    it "creates application attributes" do
      loader = described_class.new(yaml_file.path)
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
      loader = described_class.new(yaml_file.path)
      loader.load!
      loader.validate!
      loader.apply!

      pc = PartnerConfig.find_by(partner_id: "test_partner")
      expect(pc.partner_translations.where(locale: "en").count).to eq(6)
      expect(pc.partner_translations.where(locale: "es").count).to eq(6)
      acronym = pc.partner_translations.find_by(locale: "en", key: "shared.agency_acronym")
      expect(acronym.value).to eq("TEST")
    end

    it "updates an existing partner config" do
      loader = described_class.new(yaml_file.path)
      loader.load!
      loader.validate!
      loader.apply!

      valid_yaml["name"] = "Updated Agency"
      yaml_file.reopen(yaml_file.path, "w")
      yaml_file.write(valid_yaml.to_yaml)
      yaml_file.rewind

      loader2 = described_class.new(yaml_file.path)
      loader2.load!
      loader2.validate!
      changes = loader2.apply!

      expect(changes[:config]).to eq(:updated)
      expect(PartnerConfig.find_by(partner_id: "test_partner").name).to eq("Updated Agency")
    end

    it "removes application attributes not in YAML" do
      loader = described_class.new(yaml_file.path)
      loader.load!
      loader.validate!
      loader.apply!

      pc = PartnerConfig.find_by(partner_id: "test_partner")
      expect(pc.partner_application_attributes.count).to eq(2)

      valid_yaml["application_attributes"] = [ valid_yaml["application_attributes"][0] ]
      yaml_file.reopen(yaml_file.path, "w")
      yaml_file.write(valid_yaml.to_yaml)
      yaml_file.rewind

      loader2 = described_class.new(yaml_file.path)
      loader2.load!
      loader2.validate!
      changes = loader2.apply!

      expect(changes[:application_attributes][:deleted]).to eq(1)
      expect(pc.reload.partner_application_attributes.count).to eq(1)
    end

    it "resolves $ENV_VAR references in transmission config values" do
      valid_yaml["transmission_configs"] = [
        { "key" => "user", "encrypted" => true, "value" => "$TEST_APPLY_USER" }
      ]
      yaml_file.reopen(yaml_file.path, "w")
      yaml_file.write(valid_yaml.to_yaml)
      yaml_file.rewind

      ClimateControl.modify(TEST_APPLY_USER: "resolved_user") do
        loader = described_class.new(yaml_file.path)
        loader.load!
        loader.validate!
        loader.apply!
      end

      pc = PartnerConfig.find_by(partner_id: "test_partner")
      tc = pc.partner_transmission_configs.find_by(key: "user")
      expect(tc.value).to eq("resolved_user")
    end

    it "raises when $ENV_VAR is not set during apply" do
      valid_yaml["transmission_configs"] = [
        { "key" => "user", "encrypted" => true, "value" => "$MISSING_VAR_FOR_APPLY" }
      ]
      yaml_file.reopen(yaml_file.path, "w")
      yaml_file.write(valid_yaml.to_yaml)
      yaml_file.rewind

      loader = described_class.new(yaml_file.path)
      loader.load!
      loader.validate!
      expect { loader.apply! }.to raise_error(PartnerConfigLoader::ValidationError, /MISSING_VAR_FOR_APPLY/)
    end

    it "handles $$ escape for literal dollar signs" do
      valid_yaml["transmission_configs"] = [
        { "key" => "literal", "encrypted" => false, "value" => "$$NOT_AN_ENV_VAR" }
      ]
      yaml_file.reopen(yaml_file.path, "w")
      yaml_file.write(valid_yaml.to_yaml)
      yaml_file.rewind

      loader = described_class.new(yaml_file.path)
      loader.load!
      loader.validate!
      loader.apply!

      pc = PartnerConfig.find_by(partner_id: "test_partner")
      tc = pc.partner_transmission_configs.find_by(key: "literal")
      expect(tc.value).to eq("$NOT_AN_ENV_VAR")
    end

    it "returns change summary" do
      loader = described_class.new(yaml_file.path)
      loader.load!
      loader.validate!
      changes = loader.apply!

      expect(changes[:config]).to eq(:created)
      expect(changes[:transmission_configs][:created]).to eq(1)
      expect(changes[:application_attributes][:created]).to eq(2)
      expect(changes[:translations][:created]).to eq(12)
    end
  end

  describe ".export" do
    before do
      loader = described_class.new(yaml_file.path)
      loader.load!
      loader.validate!
      loader.apply!
    end

    it "exports a partner config to a hash" do
      data = described_class.export("test_partner")
      expect(data["partner_id"]).to eq("test_partner")
      expect(data["name"]).to eq("Test Agency")
      expect(data["transmission_method"]).to eq("shared_email")
    end

    it "exports application attributes" do
      data = described_class.export("test_partner")
      expect(data["application_attributes"].size).to eq(2)
      names = data["application_attributes"].map { |a| a["name"] }
      expect(names).to contain_exactly("case_number", "first_name")
    end

    it "exports translations grouped by locale" do
      data = described_class.export("test_partner")
      expect(data["translations"]["en"]["shared.agency_acronym"]).to eq("TEST")
      expect(data["translations"]["es"]["shared.agency_acronym"]).to eq("TEST")
    end

    it "uses placeholder for encrypted transmission config values" do
      valid_yaml["transmission_configs"] = [
        { "key" => "secret", "encrypted" => true, "value" => "plaintext_for_test" }
      ]
      yaml_file.reopen(yaml_file.path, "w")
      yaml_file.write(valid_yaml.to_yaml)
      yaml_file.rewind

      loader = described_class.new(yaml_file.path)
      loader.load!
      loader.validate!
      loader.apply!

      data = described_class.export("test_partner")
      secret_config = data["transmission_configs"].find { |c| c["key"] == "secret" }
      expect(secret_config["value"]).to eq("$ENCRYPTED")
    end

    it "raises for unknown partner" do
      expect { described_class.export("nonexistent") }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
