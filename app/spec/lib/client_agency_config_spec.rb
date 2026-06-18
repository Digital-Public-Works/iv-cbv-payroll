require "rails_helper"

RSpec.describe ClientAgencyConfig do
  before(:all) do
    ActiveRecord::Base.connection.disable_referential_integrity do
      # PartnerApplicationAttribute.delete_all
      # PartnerConfig.delete_all
    end
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

      it "raises an ArgumentError at agency load" do
        expect { ClientAgencyConfig.new(true) }
          .to raise_error(ArgumentError, %r{Client Agency bad_s3.*must not start with '/'})
      end
    end

    context "when path_prefix is a relative path" do
      let(:bad_prefix) { "inbox/prod" }

      it "loads without raising" do
        expect { ClientAgencyConfig.new(true) }.not_to raise_error
      end
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
end
