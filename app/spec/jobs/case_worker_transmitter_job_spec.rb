require "rails_helper"

RSpec.describe CaseWorkerTransmitterJob, type: :job do
  let(:cbv_flow) do
    create(:cbv_flow,
      :invited,
      :with_argyle_account,
      confirmation_code: "SANDBOX001"
    )
  end

  let(:agency) { instance_double(ClientAgencyConfig::ClientAgency) }
  let(:transmission_methods) do
    [
      ClientAgencyConfig::ClientAgency::TransmissionMethodEntry.new(
        method: "webhook",
        configuration: { "webhook_url" => "https://example.test/webhook", "api_key" => "abc123" }.with_indifferent_access
      ),
      ClientAgencyConfig::ClientAgency::TransmissionMethodEntry.new(
        method: "sftp",
        configuration: { "url" => "sftp.example.test", "user" => "test", "password" => "secret" }.with_indifferent_access
      )
    ]
  end

  before do
    allow_any_instance_of(described_class).to receive(:current_agency).and_return(agency)
    allow(agency).to receive(:transmission_methods).and_return(transmission_methods)
    allow(CbvFlowTransmissionAttemptJob).to receive(:perform_now)
  end

  it "creates one transmission and one attempt per configured method" do
    expect {
      described_class.new.perform(cbv_flow.id)
    }.to change(CbvFlowTransmission, :count).by(1)
      .and change(CbvFlowTransmissionAttempt, :count).by(2)

    transmission = CbvFlowTransmission.find_by!(cbv_flow: cbv_flow)
    expect(transmission.pending?).to be(true)
    expect(transmission.cbv_flow_transmission_attempts.pluck(:method_type)).to contain_exactly("webhook", "sftp")
    expect(CbvFlowTransmissionAttemptJob).to have_received(:perform_now).twice
  end

  it "raises an error when a method type is unsupported" do
    allow(agency).to receive(:transmission_methods).and_return([
      ClientAgencyConfig::ClientAgency::TransmissionMethodEntry.new(method: "smoke_signal", configuration: {})
    ])

    expect {
      described_class.new.perform(cbv_flow.id)
    }.to raise_error("Unsupported transmission method: smoke_signal")
  end

  it "reuses existing attempts and resets failed attempts to pending" do
    transmission = create(:cbv_flow_transmission, cbv_flow: cbv_flow)
    failed_attempt = create(:cbv_flow_transmission_attempt,
      cbv_flow_transmission: transmission,
      method_type: :webhook,
      status: :failed
    )

    described_class.new.perform(cbv_flow.id)

    expect(failed_attempt.reload.pending?).to be(true)
    expect(transmission.cbv_flow_transmission_attempts.where(method_type: :webhook).count).to eq(1)
  end
end
