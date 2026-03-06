require 'rails_helper'

RSpec.describe NewRelicEventTrackingJob, type: :job do
  let(:event_type) { 'TestEvent' }
  let(:attributes) { {
    time: Time.now.to_i,
    cbv_applicant_id: "applicant-1",
    cbv_flow_id: "1234",
    device_id: "ABC",
    invitation_id: "9001",
    errors: "error1, error2, error3"
  } }

  it "passes the right data to NewRelicEventTracker" do
    expect_any_instance_of(NewRelicEventTracker).to receive(:track).with(event_type, attributes)

    described_class.perform_now(event_type, attributes)
  end

  it "raises an error when it fails to create a job" do
    allow_any_instance_of(NewRelicEventTracker).to receive(:track).and_raise(StandardError.new('Test error'))
    expect { described_class.perform_now(event_type, attributes) }.to raise_error(StandardError, 'Test error')
  end
end
