require_relative "../concerns/queueable"

class ApplicationJob < ActiveJob::Base
  include Queueable

  retry_on Exception, wait: :polynomially_longer, attempts: 3

  def event_logger
    @event_logger ||= GenericEventTracker.new
  end

  # Uses https://edgeguides.rubyonrails.org/active_job_basics.html#error-reporting-on-jobs as a pattern
  # in order to send information to newrelic that we had a failed job and enable alerting on said failed job.
  rescue_from(Exception) do |error|
    NewRelic::Agent.record_custom_event(TrackEvent::QueueJobFailed, {
      job_class: (self.class.name || "UnknownJob"),
      queue_name: (self.queue_name || "default"),
      failed_at: Time.current.to_s,
      error_class: error.class.name,
      error_message: error.message
    })
    raise error
  end
end
