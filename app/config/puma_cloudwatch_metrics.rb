# frozen_string_literal: true

require "logger"

# publish puma thread pool usage to cloudwatch for autoscaling
class PumaCloudWatchMetrics
  NAMESPACE = "VMI/Puma"
  METRIC_NAME = "ThreadUtilization"
  SAMPLE_INTERVAL = 5
  SAMPLES_PER_PUBLISH = 12

  def self.start(service_name:)
    require "aws-sdk-cloudwatch"

    publisher = new(service_name: service_name, client: Aws::CloudWatch::Client.new, stats: -> { Puma.stats_hash })
    Thread.new do
      Thread.current.name = "puma cloudwatch metrics"
      publisher.run
    end
  end

  # Busy threads over max threads, as a percentage, across every Puma worker in
  # cluster mode. Nil until the server has a thread pool to report.
  def self.utilization(stats)
    servers = stat(stats, :worker_status)&.map { |worker| stat(worker, :last_status) || {} } || [ stats ]
    max_threads = servers.sum { |server| stat(server, :max_threads).to_i }
    return nil if max_threads.zero?

    busy_threads = servers.sum { |server| stat(server, :busy_threads).to_i }
    busy_threads * 100.0 / max_threads
  end

  def self.stat(hash, key)
    hash[key] || hash[key.to_s]
  end
  private_class_method :stat

  attr_reader :samples

  def initialize(service_name:, client:, stats:, logger: default_logger)
    @service_name = service_name
    @client = client
    @stats = stats
    @logger = logger
    @samples = []
  end

  def run
    loop do
      sleep SAMPLE_INTERVAL
      tick
    end
  end

  def tick
    value = self.class.utilization(@stats.call)
    @samples << value if value
    flush if @samples.size >= SAMPLES_PER_PUBLISH
  rescue => e
    @samples = []
    @logger.warn("PumaCloudWatchMetrics: #{e.class}: #{e.message}")
  end

  def flush
    values = @samples
    @samples = []
    return if values.empty?

    @client.put_metric_data(
      namespace: NAMESPACE,
      metric_data: [
        {
          metric_name: METRIC_NAME,
          dimensions: [ { name: "ServiceName", value: @service_name } ],
          timestamp: Time.now,
          unit: "Percent",
          statistic_values: {
            sample_count: values.size.to_f,
            sum: values.sum,
            minimum: values.min,
            maximum: values.max
          }
        }
      ]
    )
  end

  private

  def default_logger
    defined?(Rails) && Rails.logger ? Rails.logger : Logger.new($stderr)
  end
end
