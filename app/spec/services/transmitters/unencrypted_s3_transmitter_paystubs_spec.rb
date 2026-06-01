require "rails_helper"

RSpec.describe Transmitters::UnencryptedS3Transmitter do
  let(:cbv_applicant) { create(:cbv_applicant, case_number: "S3CASE") }
  let(:cbv_flow) do
    create(:cbv_flow,
      :invited,
      :with_argyle_account,
      cbv_applicant: cbv_applicant,
      consented_to_authorized_use_at: Time.find_zone("UTC").local(2025, 5, 1, 1),
      confirmation_code: "S3CONF1"
    )
  end

  let(:argyle_report) { build(:argyle_report, :with_argyle_account) }
  let(:aggregator_report) do
    Aggregators::AggregatorReports::CompositeReport.new(
      [ argyle_report ], days_to_fetch_for_w2: 90, days_to_fetch_for_gig: 90
    )
  end

  let(:mock_client_agency) { instance_double(ClientAgencyConfig::ClientAgency) }
  let(:s3_service) { instance_double(S3Service, upload_file: true) }

  let(:transmission_method_configuration) { {} }

  before do
    allow(mock_client_agency).to receive(:id).and_return("sandbox")
    allow(mock_client_agency).to receive(:timezone).and_return("UTC")
    allow(mock_client_agency).to receive(:applicant_attributes).and_return({})
    allow(mock_client_agency).to receive(:partner_identifier_name).and_return("case_number")
    allow(mock_client_agency).to receive(:argyle_environment).and_return("sandbox")
    allow(S3Service).to receive(:new).and_return(s3_service)
    allow_any_instance_of(PdfService).to receive(:generate)
      .and_return(OpenStruct.new(content: "fake-pdf-content", file_size: 16, page_count: 2))
  end

  subject { described_class.new(cbv_flow, mock_client_agency, aggregator_report, transmission_method_configuration) }

  context "when include_paystubs is false" do
    before { allow(mock_client_agency).to receive(:include_paystubs).and_return(false) }

    it "builds a tar bundle with exactly the pdf + csv entries" do
      tar_double = Tempfile.new("tar")
      tar_double.write("tar")
      tar_double.rewind
      expect(subject).to receive(:create_tar_file) do |file_data|
        names = file_data.map { |entry| entry[:name] }
        expect(names).to contain_exactly(/\.pdf\z/, /\.csv\z/)
        expect(names).not_to include(a_string_matching(/_paystubs\.pdf\z/))
        tar_double
      end
      subject.deliver
    end
  end

  context "when include_paystubs is true" do
    let(:paystubs_result) do
      Aggregators::PaystubsPdfService::Result.new(
        content: "fake-paystubs-pdf", page_count: 4, file_size: 18
      )
    end

    before do
      allow(mock_client_agency).to receive(:include_paystubs).and_return(true)
      allow_any_instance_of(Aggregators::PaystubsPdfService)
        .to receive(:generate).and_return(paystubs_result)
    end

    it "appends a _paystubs.pdf entry to the tar bundle" do
      tar_double = Tempfile.new("tar")
      tar_double.write("tar")
      tar_double.rewind
      expect(subject).to receive(:create_tar_file) do |file_data|
        names = file_data.map { |entry| entry[:name] }
        expect(names).to include(a_string_matching(/_paystubs\.pdf\z/))
        paystubs_entry = file_data.find { |e| e[:name].match?(/_paystubs\.pdf\z/) }
        expect(paystubs_entry[:content]).to eq("fake-paystubs-pdf")
        tar_double
      end
      subject.deliver
    end
  end
end
