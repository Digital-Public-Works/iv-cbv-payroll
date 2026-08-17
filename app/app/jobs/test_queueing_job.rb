class TestQueueingJob < ApplicationJob
  queue_as { self.class.queue_with_suffix(:report_sender) }
  def perform(random_id, fail_it = false)
    raise "Failure example" if fail_it
  end
end
