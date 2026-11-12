# send cloudwatch events for flows started and invitations created for autoscaling
class ActivityCloudWatchMetrics
  NAMESPACE = "VMI/Activity"
  METRIC_NAME = "FlowsAndInvitationsCreated"
  PUBLISH_INTERVAL = 60

  @count = 0
  @mutex = Mutex.new

  class << self
    def record(count = 1)
      @mutex.synchronize { @count += count }
    end

    # Returns the count since the last call and resets it.
    def take
      @mutex.synchronize do
        count = @count
        @count = 0
        count
      end
    end

    def start(service_name:)
      require "aws-sdk-cloudwatch"

      publisher = new(service_name: service_name, client: Aws::CloudWatch::Client.new)
      Thread.new do
        Thread.current.name = "activity cloudwatch metrics"
        publisher.run
      end
    end
  end

  def initialize(service_name:, client:, logger: Rails.logger)
    @service_name = service_name
    @client = client
    @logger = logger
  end

  def run
    loop do
      sleep PUBLISH_INTERVAL
      publish
    end
  end

  # publish 0s as well so we know when to scale down
  def publish
    count = self.class.take
    @client.put_metric_data(
      namespace: NAMESPACE,
      metric_data: [
        {
          metric_name: METRIC_NAME,
          dimensions: [ { name: "ServiceName", value: @service_name } ],
          timestamp: Time.now,
          unit: "Count",
          value: count
        }
      ]
    )
  rescue => e
    self.class.record(count) if count&.positive? # keep it for the next publish
    @logger.warn("ActivityCloudWatchMetrics: #{e.class}: #{e.message}")
  end
end
