require "rails_helper"

# Thin coverage for the partner_config rake tasks. The PartnerConfigLoader class
# is unit-tested in partner_config_loader_spec; these specs exist to exercise the
# rake tasks end-to-end so task-level bugs (e.g. calling a loader method that does
# not exist) can't silently rot — the class specs never invoke the tasks.
RSpec.describe "partner_config.rake" do
  let(:partner_id) { "wc_test" }

  let(:valid_config) do
    {
      "partner_id" => partner_id,
      "name" => "West Carolina Test",
      "timezone" => "America/Chicago",
      "domain" => "wctest",
      "argyle_environment" => "sandbox",
      "active_demo" => true,
      "active_prod" => false,
      "pay_income_days_w2" => 90,
      "pay_income_days_gig" => 90,
      "partner_identifier_name" => "case_number",
      "include_paystubs" => true,
      "transmission_methods" => [
        {
          "method_type" => "unencrypted_s3",
          "configs" => [
            { "key" => "bucket", "encrypted" => false, "value" => "test-bucket" },
            { "key" => "path_prefix", "encrypted" => false, "value" => "outout" }
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
        }
      ],
      "translations" => {
        "en" => {
          "shared.agency_acronym" => "WCT", "shared.agency_full_name" => "West Carolina Test",
          "shared.header.cbv_flow_title" => "WC", "shared.header.preheader" => "WC"
        },
        "es" => {
          "shared.agency_acronym" => "WCT", "shared.agency_full_name" => "West Carolina Test",
          "shared.header.cbv_flow_title" => "WC", "shared.header.preheader" => "WC"
        }
      }
    }
  end

  let(:source) do
    file = Tempfile.new([ "partner_config", ".yml" ])
    file.write(valid_config.to_yaml)
    file.rewind
    file
  end

  after { source.close! if source.respond_to?(:close!) }

  describe "partner_config:validate" do
    before { Rake::Task["partner_config:validate"].reenable }

    it "passes (without aborting) for a valid config" do
      expect {
        Rake::Task["partner_config:validate"].invoke(partner_id, source.path)
      }.to output(/Validation passed for #{partner_id}/).to_stdout
    end

    it "aborts when the partner_id argument does not match the file" do
      expect {
        Rake::Task["partner_config:validate"].invoke("some_other_id", source.path)
      }.to raise_error(SystemExit)
    end
  end

  describe "partner_config:apply" do
    before { Rake::Task["partner_config:apply"].reenable }

    it "creates the partner config from the YAML" do
      expect {
        Rake::Task["partner_config:apply"].invoke(partner_id, source.path)
      }.to change { PartnerConfig.where(partner_id: partner_id).count }.from(0).to(1)

      pc = PartnerConfig.find_by(partner_id: partner_id)
      expect(pc.include_paystubs).to be true
      ptm = pc.partner_transmission_methods.find_by(method_type: "unencrypted_s3")
      expect(ptm.partner_transmission_configs.find_by(key: "path_prefix").value).to eq("outout")
    end

    it "aborts without writing when the config is invalid" do
      valid_config["pay_income_days_w2"] = 45 # invalid value
      source.reopen(source.path, "w")
      source.write(valid_config.to_yaml)
      source.rewind

      expect {
        Rake::Task["partner_config:apply"].invoke(partner_id, source.path)
      }.to raise_error(SystemExit)
      expect(PartnerConfig.where(partner_id: partner_id)).not_to exist
    end
  end

  describe "partner_config:export" do
    before { Rake::Task["partner_config:export"].reenable }

    it "prints the partner's DB config as YAML" do
      create(:partner_config, partner_id: "exp_partner")

      expect {
        Rake::Task["partner_config:export"].invoke("exp_partner")
      }.to output(/partner_id: exp_partner/).to_stdout
    end
  end
end
