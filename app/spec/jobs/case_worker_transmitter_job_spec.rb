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
    allow(CbvFlowTransmissionJob).to receive(:perform_now)
  end

  it "creates one CbvFlowTransmission per configured method and enqueues a job for each" do
    expect {
      described_class.new.perform(cbv_flow.id)
    }.to change(CbvFlowTransmission, :count).by(2)

    expect(cbv_flow.cbv_flow_transmissions.pluck(:method_type)).to contain_exactly("webhook", "sftp")
    expect(cbv_flow.cbv_flow_transmissions.all?(&:pending?)).to be(true)
    expect(CbvFlowTransmissionJob).to have_received(:perform_now).twice
  end

  it "raises an error when a method type is unsupported" do
    allow(agency).to receive(:transmission_methods).and_return([
      ClientAgencyConfig::ClientAgency::TransmissionMethodEntry.new(method: "smoke_signal", configuration: {})
    ])

    expect {
      described_class.new.perform(cbv_flow.id)
    }.to raise_error("Unsupported transmission method: smoke_signal")
  end

  it "resets previously failed transmissions to pending and reuses existing rows" do
    failed = create(:cbv_flow_transmission,
      cbv_flow: cbv_flow,
      method_type: :webhook,
      status: :failed,
      last_error: "boom"
    )

    described_class.new.perform(cbv_flow.id)

    expect(failed.reload.pending?).to be(true)
    expect(cbv_flow.cbv_flow_transmissions.where(method_type: :webhook).count).to eq(1)
  end

  it "skips enqueueing jobs for transmissions already succeeded" do
    create(:cbv_flow_transmission,
      cbv_flow: cbv_flow,
      method_type: :webhook,
      status: :succeeded,
      succeeded_at: 1.hour.ago
    )

    described_class.new.perform(cbv_flow.id)

    expect(CbvFlowTransmissionJob).to have_received(:perform_now).once
  end
end
