require "rails_helper"

RSpec.describe Queueable do
  class TestQueueableJob < ApplicationJob
    include Queueable
  end
  describe ".queue_with_suffix" do
    it "appends QUEUE_SUFFIX when present" do
      with_env("QUEUE_SUFFIX", "_a11y") do
        expect(TestQueueableJob.queue_with_suffix(:report_sender)).to eq("report_sender_a11y")
      end
    end

    it "returns base queue name when QUEUE_SUFFIX is blank" do
      with_env("QUEUE_SUFFIX", "") do
        expect(TestQueueableJob.queue_with_suffix(:report_sender)).to eq("report_sender")
      end
    end

    it "returns base queue name when QUEUE_SUFFIX is not set" do
      with_env("QUEUE_SUFFIX", nil) do
        expect(TestQueueableJob.queue_with_suffix(:report_sender)).to eq("report_sender")
      end
    end

    it "converts symbol to string" do
      with_env("QUEUE_SUFFIX", "") do
        expect(TestQueueableJob.queue_with_suffix(:mixpanel_events)).to eq("mixpanel_events")
      end
    end

    it "handles string input" do
      with_env("QUEUE_SUFFIX", "_a11y") do
        expect(TestQueueableJob.queue_with_suffix("newrelic_events")).to eq("newrelic_events_a11y")
      end
    end
  end

  private

  def with_env(key, value)
    original = ENV[key]
    ENV[key] = value
    yield
  ensure
    if original.nil?
      ENV.delete(key)
    else
      ENV[key] = original
    end
  end
end
