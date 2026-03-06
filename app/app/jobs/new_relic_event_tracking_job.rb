class NewRelicEventTrackingJob < ApplicationJob
  queue_as :newrelic_events

  def perform(event_type, attributes)
    event_tracker = NewRelicEventTracker.new

    attributes[:timestamp] = self.enqueued_at&.to_datetime.to_i
    attributes[:enqueued_at] = self.enqueued_at&.to_datetime.to_i
    attributes[:processed_at] = Time.current.to_datetime.to_i

    begin
      event_tracker.track(event_type, attributes)
    rescue StandardError => e
      Rails.logger.error " Failed to perform NewRelicEventTrackingJob #{event_type}: #{e.message}"
      raise e
    end
  end
end
