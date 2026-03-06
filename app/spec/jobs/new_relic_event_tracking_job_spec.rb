require 'rails_helper'

RSpec.describe NewRelicEventTrackingJob, type: :job do
  let(:reference_time) { Time.current }
  let(:event_type) { 'TestEvent' }
  let(:attributes) { {
    time: reference_time.to_i,
    cbv_applicant_id: "applicant-1",
    cbv_flow_id: "1234",
    device_id: "ABC",
    invitation_id: "9001",
    errors: "error1, error2, error3"
  } }

  context "#perform" do
    it "passes the attributes to NewRelicEventTracker" do
      expect_any_instance_of(NewRelicEventTracker).to receive(:track).with(event_type, attributes)

      described_class.perform_now(event_type, attributes)
    end

    it "attaches the correct timestamps to the tracker" do
      travel_to(reference_time) do
        tracker = instance_double(NewRelicEventTracker)
        allow(NewRelicEventTracker).to receive(:new).and_return(tracker)

        described_class.perform_later(event_type, attributes)

        job = ActiveJob::Base.queue_adapter.enqueued_jobs.last
        actual_enqueued_at = Time.zone.parse(job["enqueued_at"])

        expected_attributes = attributes.merge(
          timestamp: actual_enqueued_at.to_i,
          enqueued_at: actual_enqueued_at.utc.iso8601,
          processed_at: reference_time.utc.iso8601
        )

        expect(tracker).to receive(:track).with(event_type, expected_attributes)
        described_class.execute(job)
      end
    end

    it "raises an error when it fails to create a job" do
      allow_any_instance_of(NewRelicEventTracker).to receive(:track).and_raise(StandardError.new('Test error'))
      expect { described_class.perform_now(event_type, attributes) }.to raise_error(StandardError, 'Test error')
    end
  end
end
