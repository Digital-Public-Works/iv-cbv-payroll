require "rails_helper"

RSpec.describe CbvFlowTransmissionFinalizeJob, type: :job do
  let(:cbv_applicant) { create(:cbv_applicant) }
  let(:cbv_flow) do
    create(:cbv_flow,
      :invited,
      :with_argyle_account,
      cbv_applicant: cbv_applicant,
      consented_to_authorized_use_at: Time.current,
      confirmation_code: "SANDBOX001"
    )
  end
  let(:transmission) { create(:cbv_flow_transmission, cbv_flow: cbv_flow) }
  let!(:attempt_a) { create(:cbv_flow_transmission_attempt, cbv_flow_transmission: transmission, method_type: :webhook, status: :succeeded) }
  let!(:attempt_b) { create(:cbv_flow_transmission_attempt, cbv_flow_transmission: transmission, method_type: :sftp, status: :succeeded) }
  let(:fake_event_logger) { instance_double(GenericEventTracker, track: nil) }

  before do
    allow_any_instance_of(described_class).to receive(:paystub_count_for).and_return(3)
    allow_any_instance_of(described_class).to receive(:event_logger).and_return(fake_event_logger)
    allow(MatchAgencyNamesJob).to receive(:perform_later)
  end

  it "sets transmitted_at and marks the transmission completed when all attempts succeeded" do
    expect {
      described_class.new.perform(transmission.id)
    }.to change { cbv_flow.reload.transmitted_at }.from(nil)

    expect(transmission.reload.completed?).to be(true)
    expect(transmission.completed_at).to be_present
    expect(fake_event_logger).to have_received(:track).with(
      "ApplicantSharedIncomeSummary",
      nil,
      hash_including(cbv_flow_id: cbv_flow.id, paystub_count: 3)
    )
  end

  it "does nothing when not all attempts succeeded" do
    attempt_b.update!(status: :failed)

    described_class.new.perform(transmission.id)

    expect(cbv_flow.reload.transmitted_at).to be_nil
    expect(transmission.reload.completed?).to be(false)
  end
end
