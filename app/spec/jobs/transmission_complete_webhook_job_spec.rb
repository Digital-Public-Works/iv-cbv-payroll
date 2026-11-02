require "rails_helper"

RSpec.describe TransmissionCompleteWebhookJob, type: :job do
  let(:succeeded_at) { Time.find_zone("UTC").local(2026, 5, 13, 18, 4, 11) }
  let(:cbv_applicant) { create(:cbv_applicant, partner_identifier: "12345") }
  let(:cbv_flow) do
    create(:cbv_flow,
      cbv_applicant: cbv_applicant,
      consented_to_authorized_use_at: Time.find_zone("UTC").local(2026, 5, 13, 14, 30),
      confirmation_code: "ABC123"
    )
  end
  let(:webhook_url) { "http://fake-state.api.gov/api/v1/income-report" }
  let(:api_key) { "test-webhook-api-key" }
  let(:webhook_configuration) { { "webhook_url" => webhook_url, "api_key" => api_key, "contract_version" => "2" } }
  let(:transmission_methods) do
    [
      ClientAgencyConfig::ClientAgency::TransmissionMethodEntry.new(method: "sftp", configuration: { "path_prefix" => "upload" }),
      ClientAgencyConfig::ClientAgency::TransmissionMethodEntry.new(method: "webhook", configuration: webhook_configuration)
    ]
  end
  let(:agency) do
    instance_double(ClientAgencyConfig::ClientAgency, id: "new-partner", timezone: "America/New_York", transmission_methods: transmission_methods)
  end
  let(:transmission) do
    create(:cbv_flow_transmission,
      cbv_flow: cbv_flow,
      method_type: :sftp,
      status: :succeeded,
      succeeded_at: succeeded_at,
      configuration: { "path_prefix" => "upload" }
    )
  end

  # WebMock may evaluate a `with` block more than once per request, so keep only
  # the last request seen and count deliveries with have_requested.
  let(:captured) { {} }
  let(:sent_body) { JSON.parse(captured[:request].body) }

  before do
    allow_any_instance_of(described_class).to receive(:agency_config).and_return({ cbv_flow.client_agency_id => agency })
    stub_request(:post, webhook_url)
      .with { |req| captured[:request] = req; true }
      .to_return(status: 200, body: '{"status": "ok"}')
  end

  it "posts a signed TransmissionComplete event to the partner's configured webhook" do
    described_class.new.perform(transmission.id)

    expect(a_request(:post, webhook_url)).to have_been_made.once
    request = captured[:request]
    expect(sent_body).to eq(
      "event_type" => "TransmissionComplete",
      "confirmation_code" => "ABC123",
      "transmission_method" => "sftp",
      "uri" => "upload/VMI_00012345_20260513_ConfABC123.pdf",
      "completed_at" => "2026-05-13T18:04:11Z"
    )
    expect(request.headers["X-Vmi-Confirmation-Code"]).to eq("ABC123")
    expect(request.headers.keys.map(&:downcase)).not_to include("x-vmi-api-key")
    expect(JsonApiSignature.verify(
      request.body,
      request.headers["X-Vmi-Timestamp"],
      request.headers["X-Vmi-Signature"],
      api_key
    )).to be(true)
  end

  it "uses the S3 object key as the uri, with no path_prefix when none is configured" do
    transmission.update!(method_type: :unencrypted_s3, configuration: {})

    described_class.new.perform(transmission.id)

    expect(sent_body).to include(
      "transmission_method" => "unencrypted_s3",
      "uri" => "VMI_00012345_20260513_ConfABC123.tar.gz"
    )
  end

  it "uses the encrypted S3 object key as the uri" do
    transmission.update!(method_type: :encrypted_s3, configuration: { "path_prefix" => "inbox" })

    described_class.new.perform(transmission.id)

    expect(sent_body).to include(
      "transmission_method" => "encrypted_s3",
      "uri" => "inbox/VMI_00012345_20260513_ConfABC123.tar.gz.gpg"
    )
  end

  it "sends a null uri for methods that do not produce a file" do
    transmission.update!(method_type: :shared_email, configuration: { "email" => "caseworker@example.com" })

    described_class.new.perform(transmission.id)

    expect(sent_body).to include(
      "transmission_method" => "shared_email",
      "uri" => nil
    )
  end

  context "when the partner has no webhook method configured" do
    let(:transmission_methods) do
      [ ClientAgencyConfig::ClientAgency::TransmissionMethodEntry.new(method: "sftp", configuration: { "path_prefix" => "upload" }) ]
    end

    it "does nothing" do
      described_class.new.perform(transmission.id)

      expect(a_request(:post, webhook_url)).not_to have_been_made
    end
  end

  it "does nothing when the partner's webhook method is on the legacy contract" do
    webhook_configuration.delete("contract_version")

    described_class.new.perform(transmission.id)

    expect(a_request(:post, webhook_url)).not_to have_been_made
  end

  it "raises on a non-success response so Shoryuken can retry" do
    stub_request(:post, webhook_url).to_return(status: 503, body: "Service Unavailable")
    allow(Rails.logger).to receive(:error)

    expect { described_class.new.perform(transmission.id) }.to raise_error(/Unexpected response from agency: 503/)
  end
end
