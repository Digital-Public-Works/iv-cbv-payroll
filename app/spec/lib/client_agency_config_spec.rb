require "rails_helper"

RSpec.describe ClientAgencyConfig do
  before(:all) do
    ActiveRecord::Base.connection.disable_referential_integrity do
      # PartnerApplicationAttribute.delete_all
      # PartnerConfig.delete_all
    end
  end

  let!(:sample_config) do
    PartnerConfig.create!(
      partner_id: 'foo',
      name: 'Foo Agency Name',
      timezone: 'America/Los_Angeles',
      argyle_environment: 'foo',
      transmission_method: 'shared_email',
      argyle_environment: 'foo',
      pay_income_days_w2: 90,
      pay_income_days_gig: 182
    )
  end

  let!(:sample_attr) do
    PartnerApplicationAttribute.create!(
      partner_config: sample_config,
      partner_id: 'foo',
      name: 'first_name',
      description: 'Applicant First Name',
      required: false,
      data_type: :string
    )
  end

  let(:sample_config_with_invitation_required) { <<~YAML }
    id: foo
    agency_name: Foo Agency Name
    timezone: America/Los_Angeles
    pinwheel:
      environment: foo
    argyle:
      environment: foo
    transmission_method: shared_email
    transmission_method_configuration:
      email: foo
    require_applicant_information_on_invitation: true
  YAML


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
