require "rails_helper"

RSpec.describe ActivityCloudWatchMetrics do
  before { described_class.take }

  describe ".record and .take" do
    it "counts records and resets when taken" do
      2.times { described_class.record }

      expect(described_class.take).to eq(2)
      expect(described_class.take).to eq(0)
    end
  end

  describe "model creation" do
    it "records a started CBV flow" do
      create(:cbv_flow)

      expect(described_class.take).to be >= 1
    end

    it "records a created invitation" do
      invitation = create(:cbv_flow_invitation)
      described_class.take

      create(:cbv_flow_invitation, user: invitation.user)

      expect(described_class.take).to eq(1)
    end

    it "does not record updates" do
      flow = create(:cbv_flow)
      described_class.take

      flow.update!(has_other_jobs: true)

      expect(described_class.take).to eq(0)
    end
  end

  describe "#publish" do
    let(:client) { Aws::CloudWatch::Client.new(stub_responses: true) }
    let(:logger) { instance_double(Logger, warn: nil) }
    let(:publisher) { described_class.new(service_name: "app-test", client: client, logger: logger) }

    it "publishes the count since the last publish" do
      3.times { described_class.record }

      publisher.publish

      request = client.api_requests.last
      expect(request[:operation_name]).to eq(:put_metric_data)
      expect(request[:params]).to include(namespace: "VMI/Activity")
      datum = request[:params][:metric_data].first
      expect(datum).to include(
        metric_name: "FlowsAndInvitationsCreated",
        dimensions: [ { name: "ServiceName", value: "app-test" } ],
        unit: "Count",
        value: 3.0
      )
      expect(described_class.take).to eq(0)
    end

    it "publishes zero when nothing happened, so idleness is explicit" do
      publisher.publish

      expect(client.api_requests.last[:params][:metric_data].first[:value]).to eq(0.0)
    end

    it "keeps the count for the next publish when CloudWatch fails" do
      client.stub_responses(:put_metric_data, "ServiceUnavailable")
      2.times { described_class.record }

      publisher.publish

      expect(logger).to have_received(:warn).with(/ActivityCloudWatchMetrics/)
      expect(described_class.take).to eq(2)
    end
  end
end
