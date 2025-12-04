require "rails_helper"

RSpec.describe ClientAgencyConfig do
  let(:config_dir) { "/fake/client-agency-config" }
  let(:foo_path)   { File.join(config_dir, "foo.yml") }
  let(:sample_config) { <<~YAML }
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
  YAML

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

  before do
    allow(Dir).to receive(:glob).and_call_original
    allow(Dir).to receive(:glob)
                    .with(File.join(config_dir, "*.yml"))
                    .and_return([ foo_path ])

    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:read)
                     .with(foo_path)
                     .and_return(sample_config)
  end

  describe "#initialize" do
    it "loads the client agency config" do
      expect do
        ClientAgencyConfig.new(config_dir, true)
      end.not_to raise_error
    end
  end

  describe "#client_agency_ids" do
    it "returns the IDs" do
      config = ClientAgencyConfig.new(config_dir, true)
      expect(config.client_agency_ids).to match_array([ "foo" ])
    end
  end

  describe "for a particular client agency" do
    it "returns the config for that agency" do
      config = ClientAgencyConfig.new(config_dir, true)
      expect(config["foo"].agency_name).to eq("Foo Agency Name")
    end
  end

  describe "#require_applicant_information_on_invitation" do
    it "defaults to false when not configured" do
      config = ClientAgencyConfig.new(config_dir, true)
      agency = config["foo"]

      expect(agency.require_applicant_information_on_invitation).to eq(false)
    end

    it "is true when configured as true" do
      allow(File).to receive(:read)
                       .with(foo_path)
                       .and_return(sample_config_with_invitation_required)

      config = ClientAgencyConfig.new(config_dir, true)
      agency = config["foo"]

      expect(agency.require_applicant_information_on_invitation).to eq(true)
    end
  end
end
