require "rails_helper"

RSpec.describe "Multi-transmission delivery", integration: true do
  include_context "gpg_setup"

  let(:cbv_applicant) do
    create(:cbv_applicant,
      case_number: "MULTI001",
      agency_id_number: "AGN002",
      beacon_id: "BCN002",
      snap_application_date: Date.new(2025, 1, 15),
      first_name: "John",
      last_name: "Smith"
    )
  end

  let(:cbv_flow) do
    create(:cbv_flow,
      :invited,
      :with_argyle_account,
      cbv_applicant: cbv_applicant,
      consented_to_authorized_use_at: Time.current,
      confirmation_code: "MULTI001",
      client_agency_id: "sandbox"
    )
  end

  let(:argyle_report) { build(:argyle_report, :with_argyle_account) }

  let(:webhook_config) do
    { "webhook_url" => "http://localhost:9292/api/v1/income-report", "api_key" => "my-secure-guid" }
  end

  let(:s3_config) do
    { "bucket" => "test-bucket", "public_key" => @public_key }
  end

  let(:mock_client_agency) do
    instance_double(ClientAgencyConfig::ClientAgency,
      id: "sandbox",
      logo_path: "",
      report_customization_show_earnings_list: true,
      transmission_methods: [
        ClientAgencyConfig::ClientAgency::TransmissionMethodEntry.new(
          method: "webhook",
          configuration: webhook_config.with_indifferent_access
        ),
        ClientAgencyConfig::ClientAgency::TransmissionMethodEntry.new(
          method: "encrypted_s3",
          configuration: s3_config.with_indifferent_access
        )
      ]
    )
  end

  before do
    allow(Aggregators::AggregatorReports::ArgyleReport).to receive(:new).and_return(argyle_report)

    allow_any_instance_of(CaseWorkerTransmitterJob).to receive(:current_agency).and_return(mock_client_agency)
    allow_any_instance_of(CaseWorkerTransmitterJob)
      .to receive(:event_logger)
      .and_return(instance_double(GenericEventTracker, track: nil))

    # Stub PDF generation — we're testing transmission, not PDF rendering
    allow_any_instance_of(PdfService).to receive(:generate)
      .and_return(OpenStruct.new(content: "fake-pdf-content"))

    # Disable local AWS SSO config so MinIO credentials take effect
    stub_const("ENV", ENV.to_h.merge(
      "AWS_ACCESS_KEY_ID" => "minioadmin",
      "AWS_SECRET_ACCESS_KEY" => "minioadmin",
      "AWS_REGION" => "us-east-1",
      "AWS_CONFIG_FILE" => "/dev/null",
      "AWS_SHARED_CREDENTIALS_FILE" => "/dev/null"
    ))

    # Point AWS SDK at MinIO
    allow(Aws::S3::Client).to receive(:new).and_wrap_original do |original, **opts|
      original.call(**opts.merge(
        endpoint: "http://localhost:9000",
        force_path_style: true,
        credentials: Aws::Credentials.new("minioadmin", "minioadmin"),
        region: "us-east-1"
      ))
    end

    WebMock.allow_net_connect!
  end

  after do
    WebMock.disable_net_connect!
  end

  it "delivers to both webhook and S3 in a single job run" do
    expect { CaseWorkerTransmitterJob.new.perform(cbv_flow.id) }.not_to raise_error

    # Verify transmitted_at was set
    expect(cbv_flow.reload.transmitted_at).to be_present

    # Verify the S3 upload happened
    s3 = Aws::S3::Client.new(
      endpoint: "http://localhost:9000",
      force_path_style: true,
      access_key_id: "minioadmin",
      secret_access_key: "minioadmin",
      region: "us-east-1"
    )

    objects = s3.list_objects_v2(bucket: "test-bucket", prefix: "outfiles/").contents
    uploaded = objects.find { |o| o.key.include?("MULTI001") && o.key.end_with?(".tar.gz.gpg") }
    expect(uploaded).to be_present
  end
end
