class ApplicationJob < ActiveJob::Base
  retry_on Exception, wait: :polynomially_longer, attempts: 3

  def event_logger
    @event_logger ||= GenericEventTracker.new
  end

  private

  # True when the ActiveJob test adapter is in use (i.e. in RSpec / the test
  # environment). Jobs that enqueue follow-up work check this so they can
  # dispatch `perform_now` synchronously inside a test — otherwise the test
  # adapter only enqueues jobs into its in-memory queue and never runs them.
  def test_queue_adapter?
    ActiveJob::Base.queue_adapter.class.name == "ActiveJob::QueueAdapters::TestAdapter"
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
