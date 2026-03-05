# frozen_string_literal: true

require "zlib"
require "faraday"
require "json"

module NewRelic
  class EventsApiClient
    BASE_URL = "https://insights-collector.newrelic.com"
    ACCOUNT_ID = ENV["NEWRELIC_ACCOUNT_ID"] || "7001719"
    API_KEY = ENV["NEWRELIC_KEY"]

    def initialize
      client_options = {
        request: {
          open_timeout: 5,
          timeout: 5,
          params_encoder: Faraday::FlatParamsEncoder
        },
        url: BASE_URL,
        headers: {
          "Content-Type" => "application/json",
          "Api-Key" => API_KEY,
          "Content-Encoding" => "gzip"
        }
      }

      @http = Faraday.new(client_options) do |conn|
        conn.response :raise_error
        conn.response :json, content_type: "application/json"
        conn.response :logger,
                      Rails.logger,
                      headers: true,
                      bodies: true,
                      log_level: :debug
        conn.adapter Faraday.default_adapter
      end
    end

    def send_event(event_type, attributes = {})
      payload = [ { eventType: event_type, **attributes } ].to_json
      compressed_body = Zlib.gzip(payload)

      path = "/v1/accounts/#{ACCOUNT_ID}/events"
      @http.post(path, compressed_body)
    end
  end
end
