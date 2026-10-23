require "rails_helper"

RSpec.describe ApplicationJob do
  class TestJob < ApplicationJob
    def perform
      raise "failed"
    end
  end

  class NonRetryableTestJob < ApplicationJob
    def perform
      raise ApplicationJob::NonRetryableError, "rejected"
    end
  end

  it "records to newrelic" do
    expect(NewRelic::Agent).to receive(:record_custom_event).with("QueueJobFailed", hash_including(retryable: true))
    expect { TestJob.perform_now }.to raise_error("failed")
  end

  context "when the job raises a NonRetryableError" do
    it "records to newrelic and doesn't re-raise, so the message isn't redelivered" do
      expect(NewRelic::Agent).to receive(:record_custom_event)
        .with("QueueJobFailed", hash_including(error_class: "ApplicationJob::NonRetryableError", error_message: "rejected", retryable: false))
      expect { NonRetryableTestJob.perform_now }.not_to raise_error
    end
  end
end
