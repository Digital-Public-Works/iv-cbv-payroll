require "rails_helper"

RSpec.describe NewRelic::EventApiClient do
  let(:client) { described_class.new }
  let(:account_id) { "7001719" }
  let(:api_key) { "TEST_API_KEY" }
  let(:expected_url) { "https://insights-collector.newrelic.com/v1/accounts/#{account_id}/events" }

  describe "#send_event" do
    let(:event_type) { "TestEvent" }
    let(:attributes) { { "speak" => "meow", "user_id" => 42 } }
    let(:requests) { WebMock::RequestRegistry.instance.requested_signatures.hash.keys }

    before do
      stub_request(:post, /#{expected_url}/)
               .to_return(status: 200, body: { "uuid" => "abc-123" }.to_json)
    end

    it "sends a gzipped JSON payload to the correct New Relic endpoint" do
      response = client.send_event(event_type, attributes)

      expect(response.status).to eq(200)
      expect(requests.first.body).to be_present

      decompressed_body = Zlib.gunzip(requests.first.body)
      json_body = JSON.parse(decompressed_body)

      expect(json_body).to be_an(Array)
      expect(json_body.first["eventType"]).to eq(event_type)
      expect(json_body.first["speak"]).to eq("meow")
    end

    it "raises a Faraday::Error when the API returns a 500" do
      stub_request(:post, expected_url).to_return(status: 500)

      expect { client.send_event(event_type, attributes) }.to raise_error(Faraday::ServerError)
    end
  end
end
