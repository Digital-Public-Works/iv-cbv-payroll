require "rails_helper"

RSpec.describe CbvFlowTransmissionJob, type: :job do
  let(:cbv_flow) do
    create(:cbv_flow,
      :invited,
      :with_argyle_account,
      consented_to_authorized_use_at: Time.current,
      confirmation_code: "SANDBOX001"
    )
  end
  let(:transmission) do
    create(:cbv_flow_transmission,
      cbv_flow: cbv_flow,
      method_type: :shared_email,
      configuration: { "email" => "caseworker@example.com" }
    )
  end
  let(:agency) { instance_double(ClientAgencyConfig::ClientAgency, id: "sandbox") }
  let(:aggregator_report) { instance_double("AggregatorReport", paystubs: []) }
  let(:transmitter) { instance_double(Transmitters::SharedEmailTransmitter, deliver: "ok") }
  let(:fake_event_logger) { instance_double(GenericEventTracker, track: nil) }

  before do
    allow_any_instance_of(described_class).to receive(:agency_config).and_return({ "sandbox" => agency })
    allow_any_instance_of(described_class).to receive(:set_aggregator_report).and_return(aggregator_report)
    allow_any_instance_of(described_class).to receive(:event_logger).and_return(fake_event_logger)
    allow(Transmitters::SharedEmailTransmitter).to receive(:new).and_return(transmitter)
    allow(MatchAgencyNamesJob).to receive(:perform_later)
  end

  it "marks the transmission succeeded and sets cbv_flow.transmitted_at on first success" do
    freeze_time do
      expect {
        described_class.new.perform(transmission.id)
      }.to change { cbv_flow.reload.transmitted_at }.from(nil).to(Time.current)

      expect(transmission.reload.succeeded?).to be(true)
      expect(transmission.succeeded_at).to eq(Time.current)
      expect(transmission.last_error).to be_nil
    end

    expect(fake_event_logger).to have_received(:track).with(
      "ApplicantSharedIncomeSummary",
      nil,
      hash_including(cbv_flow_id: cbv_flow.id)
    )
  end

  it "still tracks the event but does not overwrite transmitted_at or re-enqueue name matching when another method already succeeded" do
    original_time = 1.hour.ago
    cbv_flow.update!(transmitted_at: original_time)
    allow_any_instance_of(CbvApplicant).to receive(:agency_expected_names).and_return([ "SomeName" ])

    described_class.new.perform(transmission.id)

    expect(cbv_flow.reload.transmitted_at).to be_within(1.second).of(original_time)
    expect(fake_event_logger).to have_received(:track).with(
      "ApplicantSharedIncomeSummary",
      nil,
      hash_including(cbv_flow_id: cbv_flow.id)
    )
    expect(MatchAgencyNamesJob).not_to have_received(:perform_later)
  end

  it "rolls back the transmission update if stamping cbv_flow.transmitted_at fails" do
    allow_any_instance_of(CbvFlow).to receive(:update!).and_raise(ActiveRecord::StatementInvalid.new("boom"))

    expect {
      described_class.new.perform(transmission.id)
    }.to raise_error(ActiveRecord::StatementInvalid)

    expect(transmission.reload.succeeded?).to be(false)
    expect(cbv_flow.reload.transmitted_at).to be_nil
  end

  it "marks the transmission failed and re-raises so Shoryuken can retry" do
    allow(transmitter).to receive(:deliver).and_raise("wrong password")

    expect {
      described_class.new.perform(transmission.id)
    }.to raise_error("wrong password")

    expect(transmission.reload.failed?).to be(true)
    expect(transmission.last_error).to eq("wrong password")
    expect(cbv_flow.reload.transmitted_at).to be_nil
  end

  it "is a no-op if the transmission already succeeded" do
    transmission.update!(status: :succeeded, succeeded_at: 1.hour.ago)

    described_class.new.perform(transmission.id)

    expect(transmitter).not_to have_received(:deliver) if transmitter.respond_to?(:deliver)
  end
end
