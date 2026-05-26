require "rails_helper"

RSpec.describe "Multi-transmission delivery", integration: true do
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

  let(:webhook_config) do
    { "webhook_url" => "http://localhost:9292/api/v1/income-report", "api_key" => "my-secure-guid" }
  end

  let(:sftp_config) do
    {
      "user" => "testuser",
      "password" => "testpass",
      "url" => "localhost",
      "port" => "2222",
      "sftp_directory" => "upload"
    }
  end

  let(:encrypted_s3_config) do
    {
      "bucket" => "test-encrypted-bucket",
      "region" => "us-east-1",
      "aws_access_key_id" => "test-access-key",
      "aws_secret_access_key" => "test-secret-key",
      "public_key" => "fake-public-key"
    }
  end

  let(:unencrypted_s3_config) do
    {
      "bucket" => "test-unencrypted-bucket",
      "region" => "us-east-1",
      "aws_access_key_id" => "test-access-key",
      "aws_secret_access_key" => "test-secret-key"
    }
  end

  let(:mock_client_agency) do
    instance_double(ClientAgencyConfig::ClientAgency,
      id: "sandbox",
      logo_path: "",
      timezone: "America/New_York",
      report_customization_show_earnings_list: true,
      transmission_methods: [
        ClientAgencyConfig::ClientAgency::TransmissionMethodEntry.new(
          method: "webhook",
          configuration: webhook_config.with_indifferent_access
        ),
        ClientAgencyConfig::ClientAgency::TransmissionMethodEntry.new(
          method: "sftp",
          configuration: sftp_config.with_indifferent_access
        ),
        ClientAgencyConfig::ClientAgency::TransmissionMethodEntry.new(
          method: "encrypted_s3",
          configuration: encrypted_s3_config.with_indifferent_access
        ),
        ClientAgencyConfig::ClientAgency::TransmissionMethodEntry.new(
          method: "unencrypted_s3",
          configuration: unencrypted_s3_config.with_indifferent_access
        )
      ]
    )
  end

  let!(:created_cbv_flow) { cbv_flow }

  before do
    allow(ClientAgencyConfig.instance).to receive(:[]).and_call_original
    allow(ClientAgencyConfig.instance).to receive(:[]).with("sandbox").and_return(mock_client_agency)
  end

  it "creates a pending transmission per configured method and enqueues a job for each" do
    expect {
      CaseWorkerTransmitterJob.new.perform(cbv_flow.id)
    }.to change(CbvFlowTransmission, :count).by(4)

    transmissions = cbv_flow.reload.cbv_flow_transmissions

    expect(transmissions.pluck(:method_type)).to contain_exactly("webhook", "sftp", "encrypted_s3", "unencrypted_s3")
    expect(transmissions.all?(&:pending?)).to be(true)
    expect(CbvFlowTransmissionJob).to have_been_enqueued.exactly(4).times

    transmissions.each do |transmission|
      expect(CbvFlowTransmissionJob).to have_been_enqueued.with(transmission.id)
    end
  end

  it "skips enqueueing jobs for transmissions that already succeeded" do
    create(:cbv_flow_transmission,
      cbv_flow: cbv_flow,
      method_type: :webhook,
      status: :succeeded,
      succeeded_at: 1.hour.ago
    )

    CaseWorkerTransmitterJob.new.perform(cbv_flow.id)

    expect(CbvFlowTransmissionJob).to have_been_enqueued.exactly(3).times
  end

  it "resets failed transmissions to pending" do
    failed = create(:cbv_flow_transmission,
      cbv_flow: cbv_flow,
      method_type: :encrypted_s3,
      status: :failed,
      last_error: "connection refused"
    )

    CaseWorkerTransmitterJob.new.perform(cbv_flow.id)

    expect(failed.reload.pending?).to be(true)
    expect(CbvFlowTransmissionJob).to have_been_enqueued.exactly(4).times
  end

  it "removes transmissions for methods no longer configured" do
    orphan = create(:cbv_flow_transmission,
      cbv_flow: cbv_flow,
      method_type: :shared_email,
      status: :pending
    )

    CaseWorkerTransmitterJob.new.perform(cbv_flow.id)

    expect(CbvFlowTransmission.exists?(orphan.id)).to be(false)
    expect(cbv_flow.reload.cbv_flow_transmissions.pluck(:method_type))
      .to contain_exactly("webhook", "sftp", "encrypted_s3", "unencrypted_s3")
  end
end
