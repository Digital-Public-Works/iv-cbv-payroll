require 'rails_helper'

RSpec.describe NewRelicEventTracker do
  describe '.track' do
    let(:event_type) { 'TestEvent' }
    let(:attributes) { {
      time: Time.now.to_i,
      cbv_applicant_id: "applicant-1",
      cbv_flow_id: "1234",
      device_id: "ABC",
      invitation_id: "9001",
      errors: "error1, error2, error3"
    } }
    let(:client) { instance_double(NewRelic::EventsApiClient) }
    let(:tracker) { described_class.new(client: client) }
    let(:success_response) { instance_double(Faraday::Response, success?: true) }
    let(:requests) { WebMock::RequestRegistry.instance.requested_signatures.hash.keys }
    let(:expected_url) { "https://insights-collector.newrelic.com/v1/accounts/7001719/events" }

    before do
      stub_request(:post, /#{expected_url}/)
        .to_return(status: 200, body: { "uuid" => "abc-123" }.to_json)
    end

    it 'calls NewRelic EventsApiClient with correct parameters' do
      expect(client).to receive(:send_event).with(event_type, attributes).and_return(success_response)
      tracker.track(event_type, attributes)
    end

    context 'when an error occurs' do
      before do
        allow(client).to receive(:send_event).and_raise(Faraday::ServerError, "The system is down")
      end

      it 'logs an error message' do
        expect(Rails.logger).to receive(:error).with(/Failed to track NewRelic/)
        expect { tracker.track(event_type, attributes) }.to raise_error(Faraday::ServerError)
      end
    end
  end
end
