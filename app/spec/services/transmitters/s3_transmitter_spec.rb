require "rails_helper"

# S3Transmitter encrypts exactly when the config has a public_key. S3 is
# stubbed here; the integration specs upload to s3proxy.
RSpec.describe Transmitters::S3Transmitter do
  subject(:transmitter) { described_class.new(cbv_flow, mock_client_agency, aggregator_report, transmission_method_configuration) }

  let(:cbv_flow) do
    create(:cbv_flow,
      :invited,
      :with_argyle_account,
      cbv_applicant: create(:cbv_applicant, case_number: "S3CASE"),
      consented_to_authorized_use_at: Time.find_zone("UTC").local(2025, 5, 1, 1),
      confirmation_code: "S3CONF1"
    )
  end
  let(:aggregator_report) do
    Aggregators::AggregatorReports::CompositeReport.new(
      [ build(:argyle_report, :with_argyle_account) ], days_to_fetch_for_w2: 90, days_to_fetch_for_gig: 90
    )
  end
  let(:mock_client_agency) { instance_double(ClientAgencyConfig::ClientAgency) }
  let(:base_configuration) { { "bucket" => "reports", "region" => "us-east-1", "path_prefix" => "inbox" } }

  # What was uploaded, read during the call: the transmitter deletes the
  # tempfile right after uploading it.
  let(:uploads) { [] }
  let(:s3_service) { instance_double(S3Service) }

  before do
    allow(mock_client_agency).to receive_messages(id: "sandbox", timezone: "UTC", applicant_attributes: {}, partner_identifier_name: "case_number", argyle_environment: "sandbox", include_paystubs: false)
    allow(S3Service).to receive(:new).and_return(s3_service)
    allow(s3_service).to receive(:upload_file) do |path, key|
      uploads << { key: key, bytes: File.binread(path) }
    end
    allow_any_instance_of(PdfService).to receive(:generate)
      .and_return(OpenStruct.new(content: "fake-pdf-content", file_size: 16, page_count: 2))
  end

  def gzip?(bytes)
    bytes.byteslice(0, 2).bytes == [ 0x1f, 0x8b ]
  end

  context "when the partner has a public_key" do
    include_context "gpg_setup"

    # @public_key is set by the gpg_setup shared context's before(:all).
    let(:transmission_method_configuration) { base_configuration.merge("public_key" => @public_key) } # rubocop:disable RSpec/InstanceVariable

    it "uploads the archive GPG-encrypted, as .tar.gz.gpg" do
      transmitter.deliver

      expect(uploads.size).to eq(1)
      upload = uploads.first
      expect(upload[:key]).to eq("inbox/VMI_00S3CASE_20250501_ConfS3CONF1.tar.gz.gpg")
      expect(gzip?(upload[:bytes])).to be(false)

      decrypted = StringIO.new(+"".b)
      GPGME::Crypto.new.decrypt(StringIO.new(upload[:bytes]), output: decrypted)
      expect(gzip?(decrypted.string)).to be(true)
    end
  end

  [ nil, "", "   " ].each do |blank_key|
    context "when public_key is #{blank_key.inspect}" do
      let(:transmission_method_configuration) { base_configuration.merge("public_key" => blank_key) }

      it "uploads the unencrypted .tar.gz" do
        transmitter.deliver

        expect(uploads.map { |u| u[:key] }).to eq([ "inbox/VMI_00S3CASE_20250501_ConfS3CONF1.tar.gz" ])
        expect(gzip?(uploads.first[:bytes])).to be(true)
      end
    end
  end

  context "when there is no public_key config at all" do
    let(:transmission_method_configuration) { base_configuration }

    it "uploads the unencrypted .tar.gz" do
      transmitter.deliver

      expect(uploads.map { |u| u[:key] }).to eq([ "inbox/VMI_00S3CASE_20250501_ConfS3CONF1.tar.gz" ])
      expect(gzip?(uploads.first[:bytes])).to be(true)
    end
  end
end
