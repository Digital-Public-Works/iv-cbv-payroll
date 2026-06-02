module Queueable
  extend ActiveSupport::Concern

  class_methods do
    # Returns a queue name with environment suffix appended.
    # Appends QUEUE_SUFFIX env var to base queue name.
    #
    # Examples:
    #   queue_with_suffix(:mixpanel_events)  # => "mixpanel_events_a11y" in a11y
    #   queue_with_suffix(:report_sender)    # => "report_sender" in demo/prod
    def queue_with_suffix(base_name)
      "#{base_name}#{ENV.fetch('QUEUE_SUFFIX', '')}"
    end
  end
end
