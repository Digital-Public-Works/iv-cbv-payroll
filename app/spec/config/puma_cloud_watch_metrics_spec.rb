require "rails_helper"
require Rails.root.join("config/puma_cloudwatch_metrics")

RSpec.describe PumaCloudWatchMetrics do
  describe ".utilization" do
    it "is busy threads as a percentage of max threads in single mode" do
      expect(described_class.utilization({ busy_threads: 2, max_threads: 5 })).to eq(40.0)
    end

    it "goes over 100 when requests are queued for a thread" do
      expect(described_class.utilization({ busy_threads: 8, max_threads: 5 })).to eq(160.0)
    end

    it "combines every worker in cluster mode" do
      stats = {
        worker_status: [
          { last_status: { busy_threads: 5, max_threads: 5 } },
          { last_status: { busy_threads: 0, max_threads: 5 } }
        ]
      }
      expect(described_class.utilization(stats)).to eq(50.0)
    end

    it "accepts string keys" do
      expect(described_class.utilization({ "busy_threads" => 1, "max_threads" => 4 })).to eq(25.0)
    end

    it "is nil before the server reports a thread pool" do
      expect(described_class.utilization({})).to be_nil
      expect(described_class.utilization({ worker_status: [ { last_status: {} } ] })).to be_nil
    end
  end

  describe "sampling and publishing" do
    let(:client) { Aws::CloudWatch::Client.new(stub_responses: true) }
    let(:logger) { instance_double(Logger, warn: nil) }
    let(:busy) { [ 0 ] }
    let(:publisher) do
      described_class.new(
        service_name: "app-test",
        client: client,
        stats: -> { { busy_threads: busy.first, max_threads: 5 } },
        logger: logger
      )
    end

    def put_requests
      client.api_requests.select { |r| r[:operation_name] == :put_metric_data }
    end

    it "publishes nothing until a full minute of samples is collected" do
      (described_class::SAMPLES_PER_PUBLISH - 1).times { publisher.tick }
      expect(put_requests).to be_empty
    end

    it "publishes the minute's samples as one statistic set and starts over" do
      samples = [ 0, 5 ] + [ 1 ] * (described_class::SAMPLES_PER_PUBLISH - 2)
      samples.each do |value|
        busy[0] = value
        publisher.tick
      end

      expect(put_requests.size).to eq(1)
      params = put_requests.first[:params]
      expect(params[:namespace]).to eq("VMI/Puma")

      datum = params[:metric_data].first
      expect(datum).to include(
        metric_name: "ThreadUtilization",
        dimensions: [ { name: "ServiceName", value: "app-test" } ],
        unit: "Percent"
      )
      expect(datum[:statistic_values]).to eq(
        sample_count: described_class::SAMPLES_PER_PUBLISH.to_f,
        sum: samples.sum * 20.0,
        minimum: 0.0,
        maximum: 100.0
      )
      expect(publisher.samples).to be_empty
    end

    it "logs and drops the minute when publishing fails, without raising" do
      client.stub_responses(:put_metric_data, "AccessDenied")

      expect {
        described_class::SAMPLES_PER_PUBLISH.times { publisher.tick }
      }.not_to raise_error
      expect(logger).to have_received(:warn).with(/PumaCloudWatchMetrics: .*AccessDenied/)
      expect(publisher.samples).to be_empty
    end

    it "logs and carries on when the stats can't be read" do
      failing = described_class.new(service_name: "app-test", client: client, stats: -> { raise "no stats" }, logger: logger)

      expect { failing.tick }.not_to raise_error
      expect(logger).to have_received(:warn).with(/no stats/)
    end
  end
end
