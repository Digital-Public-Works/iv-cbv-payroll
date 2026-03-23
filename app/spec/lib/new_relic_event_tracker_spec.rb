require 'rails_helper'

RSpec.describe NewRelicEventTracker do
  describe '.track' do
    let(:event_type) { 'TestEvent' }
    let(:attributes) { {
      time: Time.current.to_i,
      cbv_applicant_id: "applicant-1",
      cbv_flow_id: "1234",
      device_id: "ABC",
      invitation_id: "9001",
      errors: "error1, error2, error3"
    } }
    let(:client) { instance_double(NewRelic::EventApiClient) }
    let(:tracker) { described_class.new(client: client) }
    let(:success_response) { instance_double(Faraday::Response, success?: true, status: 200) }
    let(:expected_url) { "https://insights-collector.newrelic.com/v1/accounts/7001719/events" }

    it "calls NewRelic EventsApiClient with correct parameters" do
      expect(client).to receive(:send_event).with(event_type, attributes).and_return(success_response)
      tracker.track(event_type, attributes)
    end

    it "creates an instance of NewRelic::EventApiClient if none is provided" do
      new_tracker = described_class.new
      expect(new_tracker.instance_variable_get(:@client)).to be_a(NewRelic::EventApiClient)
    end

    it "returns a response from the client" do
      allow(client).to receive(:send_event).and_return(success_response)
      result = tracker.track(event_type, attributes)
      expect(result).to eq(success_response)
    end

    context "when an error occurs" do
      it "logs an error for a Faraday level error" do
        allow(client).to receive(:send_event).and_raise(Faraday::ServerError, "The system is down")
        expect(Rails.logger).to receive(:error).with(/Failed to track NewRelic/)
        expect { tracker.track(event_type, attributes) }.to raise_error(Faraday::ServerError)
      end

      context "because the NewRelic API returned an error" do
        it "logs an error message for HTTP errors" do
          http_error = (instance_double(Faraday::Response, success?: false, status: 500))
          allow(client).to receive(:send_event).and_return(http_error)

          expect(Rails.logger).to receive(:error).with(/Retryable NewRelic API error/)
          expect { tracker.track(event_type, attributes) }.to raise_error(RuntimeError, /Retryable NewRelic API error/)
        end

        it "logs an error message for a fatal error and does not raise an exception" do
          http_error = (instance_double(Faraday::Response, success?: false, status: 400))
          allow(client).to receive(:send_event).and_return(http_error)

          expect(Rails.logger).to receive(:error).with(/Check content or license key/)
          expect { tracker.track(event_type, attributes) }.not_to raise_error
        end

        it "logs an error for an unhandled code" do
          http_error = (instance_double(Faraday::Response, success?: false, status: 402))
          allow(client).to receive(:send_event).and_return(http_error)

          expect(Rails.logger).to receive(:error).with(/Unknown/)
          expect { tracker.track(event_type, attributes) }.to raise_error(RuntimeError, /Unknown/)
        end
      end
    end
  end
end
