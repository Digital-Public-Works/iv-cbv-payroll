# Sends signed webhook events to a partner's webhook_url: the ReportSubmission
# (via #deliver) and TransmissionComplete events (via .post_event, from
# TransmissionCompleteWebhookJob).
#
# The wire format depends on the optional contract_version key on the partner's
# webhook transmission method config:
#   "1" (default) - the legacy contract existing consumers rely on: the body is
#                   the bare income report and the api_key is sent in the
#                   X-VMI-API-Key header. Only ReportSubmission exists.
#   "2"           - the body carries a top-level event_type (ReportSubmission or
#                   TransmissionComplete), and the api_key is only the HMAC
#                   secret for X-VMI-Signature; it is never sent.
class Transmitters::WebhookTransmitter
  include Transmitter

  REPORT_SUBMISSION = "ReportSubmission".freeze
  TRANSMISSION_COMPLETE = "TransmissionComplete".freeze

  # Responses that mean the transmission got there but the partner rejected it. Don't retry
  NON_RETRYABLE_STATUS_CODES = %w[400 413 422].freeze

  class NonRetryableResponseError < ApplicationJob::NonRetryableError; end

  LEGACY_CONTRACT_VERSION = "1".freeze
  EVENTS_CONTRACT_VERSION = "2".freeze
  CONTRACT_VERSIONS = [ LEGACY_CONTRACT_VERSION, EVENTS_CONTRACT_VERSION ].freeze

  # The partner's webhook transmission method config when it is on the events
  # contract, i.e. when TransmissionComplete events should be sent; otherwise nil.
  def self.events_contract_config(current_agency)
    webhook_method = current_agency.transmission_methods.find { |entry| entry.method.to_s == "webhook" }
    return nil unless webhook_method

    config = webhook_method.configuration
    events_contract?(config) ? config : nil
  end

  def self.events_contract?(transmission_config)
    transmission_config.with_indifferent_access["contract_version"].to_s == EVENTS_CONTRACT_VERSION
  end

  def self.post_event(transmission_config, event_type:, confirmation_code:, payload:)
    config = transmission_config.with_indifferent_access
    events_contract = events_contract?(config)
    webhook_url = URI(config["webhook_url"])
    api_key = config["api_key"]

    req = Net::HTTP::Post.new(webhook_url)
    req.content_type = "application/json"
    req.body = (events_contract ? { event_type: event_type }.merge(payload) : payload).to_json

    timestamp = Time.now.to_i.to_s
    req["X-VMI-Timestamp"] = timestamp
    req["X-VMI-Signature"] = JsonApiSignature.generate(req.body, timestamp, api_key)
    req["X-VMI-API-Key"] = api_key unless events_contract
    req["X-VMI-Confirmation-Code"] = confirmation_code

    res = Net::HTTP.start(webhook_url.hostname, webhook_url.port, use_ssl: webhook_url.scheme == "https") do |http|
      http.request(req)
    end

    case res
    when Net::HTTPSuccess
      "ok"
    else
      Rails.logger.error "Unexpected response: #{res.code} #{res.message}"
      Rails.logger.error "  Body: #{res.body}"
      error_class = NON_RETRYABLE_STATUS_CODES.include?(res.code) ? NonRetryableResponseError : RuntimeError
      raise error_class, "Unexpected response from agency: #{res.code} #{res.message}"
    end
  end

  def deliver
    self.class.post_event(
      @transmission_config,
      event_type: REPORT_SUBMISSION,
      confirmation_code: @cbv_flow.confirmation_code,
      payload: CbvFlowToJson.new(@cbv_flow, @current_agency, @aggregator_report).to_h
    )
  end
end
