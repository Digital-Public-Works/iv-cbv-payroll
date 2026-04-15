require "rails_helper"

RSpec.describe Transmitters::EncryptedS3Transmitter, integration: true do
  include_context "gpg_setup"

  let(:cbv_applicant) do
    create(:cbv_applicant,
      case_number: "ABC1234",
      agency_id_number: "AGN001",
      beacon_id: "BCN001",
      snap_application_date: Date.new(2025, 1, 15),
      first_name: "Jane",
      last_name: "Doe"
    )
  end

  let(:cbv_flow) do
    create(:cbv_flow,
      :invited,
      :with_argyle_account,
      cbv_applicant: cbv_applicant,
      consented_to_authorized_use_at: Time.current,
      confirmation_code: "S3TEST01",
      client_agency_id: "sandbox"
    )
  end

  let(:mock_client_agency) { instance_double(ClientAgencyConfig::ClientAgency) }
  let(:argyle_report) { build(:argyle_report, :with_argyle_account) }
  let(:aggregator_report) do
    Aggregators::AggregatorReports::CompositeReport.new(
      [argyle_report],
      days_to_fetch_for_w2: 90,
      days_to_fetch_for_gig: 90
    )
  end

  let(:transmission_config) do
    {
      "bucket" => "test-bucket",
      "public_key" => @public_key
    }
  end

  before do
    allow(mock_client_agency).to receive(:id).and_return("sandbox")
    allow(mock_client_agency).to receive(:logo_path).and_return("")
    allow(mock_client_agency).to receive(:report_customization_show_earnings_list).and_return(true)

    # Stub PDF generation — we're testing S3 upload/encryption, not PDF rendering
    allow_any_instance_of(PdfService).to receive(:generate)
      .and_return(OpenStruct.new(content: "fake-pdf-content"))

    # Point the AWS SDK at the local MinIO instance
    stub_const("ENV", ENV.to_h.merge(
      "AWS_ACCESS_KEY_ID" => "minioadmin",
      "AWS_SECRET_ACCESS_KEY" => "minioadmin",
      "AWS_REGION" => "us-east-1",
      "AWS_CONFIG_FILE" => "/dev/null",
      "AWS_SHARED_CREDENTIALS_FILE" => "/dev/null"
    ))

    allow(Aws::S3::Client).to receive(:new).and_wrap_original do |original, **opts|
      original.call(**opts.merge(
        endpoint: "http://localhost:9000",
        force_path_style: true,
        credentials: Aws::Credentials.new("minioadmin", "minioadmin"),
        region: "us-east-1"
      ))
    end
  end

  subject { described_class.new(cbv_flow, mock_client_agency, aggregator_report, transmission_config) }

  describe "#deliver" do
    it "encrypts and uploads a .tar.gz.gpg file to MinIO" do
      expect { subject.deliver }.not_to raise_error

      # Verify the file actually landed in MinIO
      s3 = Aws::S3::Client.new(
        endpoint: "http://localhost:9000",
        force_path_style: true,
        access_key_id: "minioadmin",
        secret_access_key: "minioadmin",
        region: "us-east-1"
      )

      objects = s3.list_objects_v2(bucket: "test-bucket", prefix: "outfiles/").contents
      expect(objects).not_to be_empty

      uploaded = objects.find { |o| o.key.end_with?(".tar.gz.gpg") }
      expect(uploaded).to be_present
      expect(uploaded.key).to include("AGN001")
      expect(uploaded.key).to include("S3TEST01")
    end
  end
end
