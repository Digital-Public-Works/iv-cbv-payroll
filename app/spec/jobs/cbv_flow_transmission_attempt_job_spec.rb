require "rails_helper"

RSpec.describe CbvFlowTransmissionAttemptJob, type: :job do
  let(:cbv_flow) do
    create(:cbv_flow,
      :invited,
      :with_argyle_account,
      consented_to_authorized_use_at: Time.current,
      confirmation_code: "SANDBOX001"
    )
  end
  let(:transmission) { create(:cbv_flow_transmission, cbv_flow: cbv_flow) }
  let(:attempt) do
    create(:cbv_flow_transmission_attempt,
      cbv_flow_transmission: transmission,
      method_type: :shared_email,
      configuration: { "email" => "caseworker@example.com" }
    )
  end
  let(:agency) { instance_double(ClientAgencyConfig::ClientAgency, id: "sandbox") }
  let(:aggregator_report) { instance_double("AggregatorReport", paystubs: []) }
  let(:transmitter) { instance_double(Transmitters::SharedEmailTransmitter, deliver: "ok") }

  before do
    allow_any_instance_of(described_class).to receive(:agency_config).and_return({ "sandbox" => agency })
    allow_any_instance_of(described_class).to receive(:set_aggregator_report).and_return(aggregator_report)
    allow(Transmitters::SharedEmailTransmitter).to receive(:new).and_return(transmitter)
    allow(CbvFlowTransmissionFinalizeJob).to receive(:perform_now)
  end

  it "marks the attempt succeeded and enqueues finalization on success" do
    described_class.new.perform(attempt.id)

    expect(attempt.reload.succeeded?).to be(true)
    expect(attempt.attempt_count).to eq(1)
    expect(attempt.last_error).to be_nil
    expect(CbvFlowTransmissionFinalizeJob).to have_received(:perform_now).with(transmission.id)
  end

  it "marks the attempt failed and raises on error" do
    allow(transmitter).to receive(:deliver).and_raise("boom")

    expect {
      described_class.new.perform(attempt.id)
    }.to raise_error("boom")

    expect(attempt.reload.failed?).to be(true)
    expect(attempt.last_error).to eq("boom")
    expect(transmission.reload.failed?).to be(true)
  end
end
