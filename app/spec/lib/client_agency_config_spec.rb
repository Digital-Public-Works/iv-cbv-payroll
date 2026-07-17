require "rails_helper"

RSpec.describe ClientAgencyConfig do
  before(:all) do
    ActiveRecord::Base.connection.disable_referential_integrity do
      # PartnerApplicationAttribute.delete_all
      # PartnerConfig.delete_all
    end
  end

  before do
    # Avoid reporting validation warnings to New Relic during these specs.
    allow(NewRelic::Agent).to receive(:notice_error) if defined?(NewRelic::Agent)
  end

  let!(:sample_config) do
    pc = PartnerConfig.create!(
      partner_id: 'foo',
      name: 'Foo Agency Name',
      timezone: 'America/Los_Angeles',
      argyle_environment: 'foo',
      pay_income_days_w2: 90,
      pay_income_days_gig: 182,
      partner_identifier_name: 'first_name'
    )
    pc.partner_transmission_methods.create!(method_type: :shared_email)
    pc
  end

  let!(:sample_attr) do
    PartnerApplicationAttribute.create!(
      partner_config: sample_config,
      name: 'first_name',
      description: 'Applicant First Name',
      required: false,
      data_type: :string
    )
  end

  describe "#initialize" do
    it "loads the client agency config" do
      expect do
        ClientAgencyConfig.new(true)
      end.not_to raise_error
    end
  end

  describe "#client_agency_ids" do
    it "returns the IDs" do
      config = ClientAgencyConfig.new(true)
      expect(config.client_agency_ids).to include("foo")
    end
  end

  describe "for a particular client agency" do
    it "returns the config for that agency" do
      config = ClientAgencyConfig.new(true)
      expect(config["foo"].agency_name).to eq("Foo Agency Name")
    end
  end

  describe "path_prefix validation for s3 transmission methods" do
    let!(:s3_partner) do
      pc = PartnerConfig.create!(
        partner_id: "bad_s3",
        name: "Bad S3 Partner",
        timezone: "America/Los_Angeles",
        argyle_environment: "sandbox",
        pay_income_days_w2: 90,
        pay_income_days_gig: 90,
        partner_identifier_name: "first_name"
      )
      ptm = pc.partner_transmission_methods.create!(method_type: :encrypted_s3)
      ptm.partner_transmission_configs.create!(key: "path_prefix", value: bad_prefix, is_encrypted: false)
      pc
    end

    context "when path_prefix starts with /" do
      let(:bad_prefix) { "/inbox" }

      it "is unavailable and logs an error instead of raising when requested" do
        allow(Rails.logger).to receive(:error)
        config = ClientAgencyConfig.new(true)

        result = nil
        expect { result = config["bad_s3"] }.not_to raise_error
        expect(result).to be_nil
        expect(Rails.logger).to have_received(:error)
          .with(%r{bad_s3 failed validation.*must not start with '/'}).at_least(:once)
      end

      it "logs the failure during the boot validation pass without raising" do
        allow(Rails.logger).to receive(:error)

        expect { ClientAgencyConfig.new(true).validate_all }.not_to raise_error
        expect(Rails.logger).to have_received(:error)
          .with(%r{bad_s3 failed validation.*must not start with '/'})
      end
    end

    context "when path_prefix is a relative path" do
      let(:bad_prefix) { "inbox/prod" }

      it "loads the agency without raising" do
        config = ClientAgencyConfig.new(true)
        expect(config["bad_s3"]).to be_present
      end
    end
  end

  describe "lazy loading" do
    it "does not construct any agency when the instance is created" do
      expect(ClientAgencyConfig::ClientAgency).not_to receive(:new)
      ClientAgencyConfig.new(true)
    end

    it "loads an agency from the database on first access and memoizes it" do
      config = ClientAgencyConfig.new(true)

      expect(PartnerConfig).to receive(:find_by).with(partner_id: "foo").once.and_call_original

      2.times { expect(config["foo"].agency_name).to eq("Foo Agency Name") }
    end

    it "returns nil for an unknown agency and does not cache the miss" do
      config = ClientAgencyConfig.new(true)

      expect(PartnerConfig).to receive(:find_by).with(partner_id: "ghost").exactly(2).times.and_call_original

      expect(config["ghost"]).to be_nil
      expect(config["ghost"]).to be_nil
    end

    it "returns nil for a blank id without touching the database" do
      config = ClientAgencyConfig.new(true)

      expect(PartnerConfig).not_to receive(:find_by)

      expect(config[nil]).to be_nil
      expect(config[""]).to be_nil
    end

    it "serves a cached agency without re-querying while the entry is fresh" do
      config = ClientAgencyConfig.new(true)
      fake_time = 0.0
      allow(config).to receive(:now) { fake_time }

      expect(PartnerConfig).to receive(:find_by).with(partner_id: "foo").once.and_call_original

      config["foo"]
      fake_time = ClientAgencyConfig::CACHE_TTL_SECONDS - 1
      config["foo"]
    end

    it "reloads on every lookup in development so config edits are immediate" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      config = ClientAgencyConfig.new(true)

      expect(PartnerConfig).to receive(:find_by).with(partner_id: "foo").twice.and_call_original

      config["foo"]
      config["foo"]
    end

    it "picks up database changes after the cache TTL expires" do
      config = ClientAgencyConfig.new(true)
      fake_time = 0.0
      allow(config).to receive(:now) { fake_time }

      expect(config["foo"].agency_name).to eq("Foo Agency Name")

      sample_config.update!(name: "Renamed Foo Agency")

      # Still within the TTL: the cached value is returned.
      fake_time = ClientAgencyConfig::CACHE_TTL_SECONDS - 1
      expect(config["foo"].agency_name).to eq("Foo Agency Name")

      # Past the TTL: the agency is reloaded from the database.
      fake_time = ClientAgencyConfig::CACHE_TTL_SECONDS + 1
      expect(config["foo"].agency_name).to eq("Renamed Foo Agency")
    end
  end

  describe "#find_by_domain" do
    it "resolves an agency by its configured domain" do
      config = ClientAgencyConfig.new(true)
      agency = config.find_by_domain("sandbox")

      expect(agency).to be_present
      expect(agency.id).to eq("sandbox")
    end

    it "returns nil for an unrecognized domain" do
      config = ClientAgencyConfig.new(true)
      expect(config.find_by_domain("not-a-domain")).to be_nil
    end
  end

  describe "#require_applicant_information_on_invitation" do
    it "defaults to false when not configured" do
      config = ClientAgencyConfig.new(true)
      agency = config["foo"]

      expect(agency.require_applicant_information_on_invitation).to eq(false)
    end

    it "is true when configured as true" do
      sample_attr.update!(required: true)
      config = ClientAgencyConfig.new(true)
      agency = config["foo"]

      expect(agency.require_applicant_information_on_invitation).to eq(true)
    end
  end

  describe "#validate_all" do
    let!(:partner_without_attributes) do
      pc = PartnerConfig.create!(
        partner_id: 'no_attrs',
        name: 'No Attributes Agency',
        timezone: 'America/Los_Angeles',
        argyle_environment: 'sandbox',
        pay_income_days_w2: 90,
        pay_income_days_gig: 90,
        partner_identifier_name: 'first_name'
      )
      pc.partner_transmission_methods.create!(method_type: :shared_email)
      pc
    end

    it "logs an error for a partner missing application attributes without raising" do
      allow(Rails.logger).to receive(:error)

      expect { ClientAgencyConfig.new(true).validate_all }.not_to raise_error
      expect(Rails.logger).to have_received(:error)
        .with(/no_attrs has no partner_application_attributes/)
    end

    it "warns lazily on the live request that loads the misconfigured partner" do
      allow(Rails.logger).to receive(:error)
      config = ClientAgencyConfig.new(true)

      expect(config["no_attrs"]).to be_present
      expect(Rails.logger).to have_received(:error)
        .with(/no_attrs has no partner_application_attributes/)
    end
  end
end
