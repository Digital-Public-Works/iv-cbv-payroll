require "rails_helper"

RSpec.describe Transmitters::SftpTransmitter do
  let(:consented_at) { Time.find_zone("UTC").local(2025, 5, 1, 1) }
  let(:cbv_flow) do
    create(:cbv_flow, :invited, :with_argyle_account,
      confirmation_code: "SFTP001",
      consented_to_authorized_use_at: consented_at)
  end
  let(:argyle_report) { build(:argyle_report, :with_argyle_account) }
  let(:aggregator_report) do
    Aggregators::AggregatorReports::CompositeReport.new(
      [ argyle_report ], days_to_fetch_for_w2: 90, days_to_fetch_for_gig: 90
    )
  end

  let(:mock_client_agency) { instance_double(ClientAgencyConfig::ClientAgency) }
  let(:sftp_gateway) { instance_double(SftpGateway) }
  let(:transmission_method_configuration) { { "path_prefix" => "upload" } }

  let(:expected_filename) { TransmissionFilename.basename_for(cbv_flow: cbv_flow, agency: mock_client_agency, method_type: :sftp) }
  let(:expected_paystubs_filename) { TransmissionFilename.basename_for(cbv_flow: cbv_flow, agency: mock_client_agency, method_type: :sftp, suffix: "_paystubs") }

  before do
    allow(mock_client_agency).to receive(:id).and_return("sandbox")
    allow(mock_client_agency).to receive(:timezone).and_return("UTC")
    allow(mock_client_agency).to receive(:argyle_environment).and_return("sandbox")
    allow(SftpGateway).to receive(:new).and_return(sftp_gateway)
    allow(sftp_gateway).to receive(:upload_data)
    allow_any_instance_of(PdfService).to receive(:generate)
      .and_return(OpenStruct.new(content: "fake-pdf-content"))
  end

  subject { described_class.new(cbv_flow, mock_client_agency, aggregator_report, transmission_method_configuration) }

  context "when include_paystubs is false" do
    before { allow(mock_client_agency).to receive(:include_paystubs).and_return(false) }

    it "uploads only the report PDF" do
      subject.deliver
      expect(sftp_gateway).to have_received(:upload_data).once
      expect(sftp_gateway).to have_received(:upload_data)
        .with(kind_of(StringIO), "upload/#{expected_filename}")
    end
  end

  context "when include_paystubs is true" do
    let(:paystubs_result) do
      Aggregators::PaystubsPdfService::Result.new(
        content: "fake-paystubs-pdf", page_count: 3, file_size: 17
      )
    end

    before do
      allow(mock_client_agency).to receive(:include_paystubs).and_return(true)
      allow_any_instance_of(Aggregators::PaystubsPdfService)
        .to receive(:generate).and_return(paystubs_result)
    end

    it "uploads both the report and the paystubs bundle" do
      subject.deliver
      expect(sftp_gateway).to have_received(:upload_data)
        .with(kind_of(StringIO), "upload/#{expected_filename}")
      expect(sftp_gateway).to have_received(:upload_data)
        .with(kind_of(StringIO), "upload/#{expected_paystubs_filename}")
    end
  end
end
