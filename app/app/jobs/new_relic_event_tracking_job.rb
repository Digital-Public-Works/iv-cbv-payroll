class NewRelicEventTrackingJob < ApplicationJob
  queue_as { self.class.queue_with_suffix(:newrelic_events) }

  def perform(event_type, attributes)
    event_tracker = NewRelicEventTracker.new

    attributes[:timestamp] = self.enqueued_at&.to_datetime.to_i
    attributes[:enqueued_at] = self.enqueued_at&.utc&.iso8601
    attributes[:processed_at] = Time.current.utc.iso8601

    begin
      event_tracker.track(event_type, attributes)
    rescue StandardError => e
      Rails.logger.error " Failed to perform NewRelicEventTrackingJob #{event_type}: #{e.message}"
      raise e
    end
  end
end
