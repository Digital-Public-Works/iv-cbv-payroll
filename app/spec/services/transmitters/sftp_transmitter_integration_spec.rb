require "rails_helper"

RSpec.describe Transmitters::SftpTransmitter, integration: true do
  let(:cbv_applicant) { create(:cbv_applicant, case_number: "ABC1234") }
  let(:cbv_flow) do
    create(:cbv_flow,
      :invited,
      :with_argyle_account,
      cbv_applicant: cbv_applicant,
      consented_to_authorized_use_at: Time.current,
      confirmation_code: "SFTP001",
      client_agency_id: "pa_dhs"
    )
  end

  let(:mock_client_agency) { instance_double(ClientAgencyConfig::ClientAgency) }
  let(:argyle_report) { build(:argyle_report, :with_argyle_account) }
  let(:aggregator_report) do
    Aggregators::AggregatorReports::CompositeReport.new(
      [ argyle_report ],
      days_to_fetch_for_w2: 90,
      days_to_fetch_for_gig: 90
    )
  end

  let(:transmission_method_configuration) do
    {
      "user" => "testuser",
      "password" => "testpass",
      "url" => "localhost",
      "port" => "2222",
      "sftp_directory" => "upload"
    }
  end

  before do
    allow(mock_client_agency).to receive(:id).and_return("pa_dhs")
    allow(mock_client_agency).to receive(:logo_path).and_return("pa_compass_logo.svg")
    allow(mock_client_agency).to receive(:report_customization_show_earnings_list).and_return(true)
    allow(mock_client_agency).to receive(:timezone).and_return("America/New_York")
    allow(mock_client_agency).to receive(:pdf_filename).and_return("test_report")

    # Stub PDF generation — we're testing SFTP upload, not PDF rendering
    allow_any_instance_of(PdfService).to receive(:generate)
      .and_return(OpenStruct.new(content: "fake-pdf-content"))

    # Use password-only auth to avoid scanning local ~/.ssh keys (which may
    # include ed25519 keys that require an optional gem not in the bundle).
    allow(Net::SSH).to receive(:start).and_wrap_original do |original, host, user, **opts|
      original.call(host, user, **opts.merge(
        verify_host_key: :never,
        keys: [],
        auth_methods: %w[password]
      ))
    end
  end

  subject { described_class.new(cbv_flow, mock_client_agency, aggregator_report, transmission_method_configuration) }

  describe "#deliver" do
    it "uploads a PDF to the SFTP server" do
      expect { subject.deliver }.not_to raise_error
    end
  end
end
