require "rails_helper"

RSpec.describe NewRelic::EventLogger do
  describe ".track" do
    let(:event_type) { "TestEvent" }
    let(:attributes) { { "speak" => "meow", "user_id" => 42 } }
    let(:logger) { described_class }

    it "calls NewRelicEventTrackingJob with event type and attributes" do
      expect(NewRelicEventTrackingJob).to receive(:perform_later).with(event_type, attributes)
      logger.track(event_type, attributes)
    end

    it "raises an error if it fails to create a tracking job when not in prod" do
      allow(Rails.env).to receive(:production?).and_return(false)
      expect(NewRelicEventTrackingJob).to receive(:perform_later).with(event_type, attributes)
                                                                 .and_raise(StandardError.new('Test error'))
      expect { logger.track(event_type, attributes) }.to raise_error(StandardError, 'Test error')
    end

    it 'logs an error but does not raise when in prod' do
      allow(Rails.env).to receive(:production?).and_return(true)

      expect(NewRelicEventTrackingJob).to receive(:perform_later).with(event_type, attributes)
                                                                 .and_raise(StandardError.new('Test error'))
      expect { logger.track(event_type, attributes) }.to_not raise_error(StandardError, 'Test error')
    end
  end
end
