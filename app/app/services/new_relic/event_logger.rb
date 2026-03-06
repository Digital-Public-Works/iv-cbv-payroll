module NewRelic
  class EventLogger
    def self.track(event_type, attributes = {})
      NewRelicEventTrackingJob.perform_later(event_type, attributes)

    rescue => e
      Rails.logger.error "Failure to enqueue New Relic event tracking job (#{event_type}: #{e}, line: #{e.backtrace&.first})"
      raise e unless Rails.env.production?
    end
  end
end
