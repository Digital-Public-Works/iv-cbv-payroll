require "rails_helper"

RSpec.describe Transmitters::UnencryptedS3Transmitter, integration: true do
  let(:cbv_applicant) { create(:cbv_applicant, case_number: "S3UNENC1") }
  let(:cbv_flow) do
    create(:cbv_flow,
      :invited,
      :with_argyle_account,
      cbv_applicant: cbv_applicant,
      consented_to_authorized_use_at: Time.current,
      confirmation_code: "S3UNENC1",
      client_agency_id: "sandbox"
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

  let(:bucket) { "test-unencrypted-bucket" }
  let(:transmission_method_configuration) do
    {
      "bucket" => bucket,
      "region" => "us-east-1",
      "aws_access_key_id" => "s3test",
      "aws_secret_access_key" => "s3test",
      "endpoint" => ENV.fetch("S3_ENDPOINT", "http://localhost:9000"),
      "force_path_style" => true
    }
  end

  before do
    allow(mock_client_agency).to receive(:id).and_return("sandbox")
    allow(mock_client_agency).to receive(:logo_path).and_return("")
    allow(mock_client_agency).to receive(:report_customization_show_earnings_list).and_return(true)
    allow(mock_client_agency).to receive(:timezone).and_return("America/New_York")
    allow(mock_client_agency).to receive(:partner_identifier_name).and_return("case_number")
    allow(mock_client_agency).to receive(:applicant_attributes).and_return({})

    stub_pdf_generation(label: "UnencryptedS3Transmitter integration test")
  end

  subject { described_class.new(cbv_flow, mock_client_agency, aggregator_report, transmission_method_configuration) }

  describe "#deliver" do
    it "uploads a tar.gz archive whose contents match what was generated" do
      expect { subject.deliver }.not_to raise_error

      s3 = s3_client_from(transmission_method_configuration)
      keys = s3.list_objects_v2(bucket: bucket).contents.map(&:key)
      key = keys.grep(/\AVMI_[A-Z0-9]{8}_\d{8}_ConfS3UNENC1\.tar\.gz\z/).max
      expect(key).not_to be_nil, "no VMI tar.gz landed in the bucket; saw: #{keys.inspect}"

      entries = extract_tar_gz(download_object(s3, bucket, key))
      expect(entries.keys).to contain_exactly(
        a_string_matching(/\.pdf\z/),
        a_string_matching(/\.csv\z/)
      )

      pdf_name, pdf_bytes = entries.find { |k, _| k.end_with?(".pdf") }
      csv_name, csv_bytes = entries.find { |k, _| k.end_with?(".csv") }
      expect(File.basename(pdf_name, ".pdf")).to eq(File.basename(csv_name, ".csv"))

      # PDF is real, parseable, and has at least one page.
      expect(pdf_bytes.byteslice(0, 5)).to eq("%PDF-")
      expect(PDF::Reader.new(StringIO.new(pdf_bytes)).page_count).to be >= 1

      # CSV metadata matches the cbv_flow / applicant we transmitted.
      meta = parse_metadata_csv(csv_bytes)
      expect(meta["case_number"]).to eq("S3UNENC1")
      expect(meta["confirmation_code"]).to eq("S3UNENC1")
      expect(meta["pdf_filename"]).to eq(pdf_name)
      expect(meta["pdf_filetype"]).to eq("application/pdf")
      expect(meta["pdf_filesize"].to_i).to eq(pdf_bytes.bytesize)
      expect(meta["pdf_number_of_pages"].to_i).to be >= 1
    end
  end

  describe "with bad credentials" do
    it "fails the transmission and records the error" do
      bad_config = transmission_method_configuration.merge(
        "aws_access_key_id" => "wrong-key",
        "aws_secret_access_key" => "wrong-secret"
      )
      transmission = create(:cbv_flow_transmission,
        cbv_flow: cbv_flow,
        method_type: :unencrypted_s3,
        status: :pending,
        configuration: bad_config
      )

      # Use the real ClientAgencyConfig — the live "sandbox" config supplies
      # the agency methods the deliver path needs. Only stub the two
      # job-internal helpers we can't run for real.
      allow_any_instance_of(CbvFlowTransmissionJob).to receive(:set_aggregator_report).and_return(aggregator_report)
      allow_any_instance_of(CbvFlowTransmissionJob).to receive(:event_logger)
        .and_return(instance_double(GenericEventTracker, track: nil))

      expect {
        CbvFlowTransmissionJob.new.perform(transmission.id)
      }.to raise_error(Aws::S3::Errors::ServiceError)

      transmission.reload
      expect(transmission).to be_failed
      expect(transmission.last_error).to be_present
      expect(transmission.succeeded_at).to be_nil
      expect(cbv_flow.reload.transmitted_at).to be_nil
    end
  end
end
