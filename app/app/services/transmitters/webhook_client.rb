# Signs and POSTs a single webhook event to a partner's webhook_url. Every
# webhook VMI sends goes through here.
#
# The wire format depends on the optional contract_version key on the partner's
# webhook transmission method config:
#   "1" (default) - the legacy contract existing consumers rely on: the body is
#                   the bare income report and the api_key is sent in the
#                   X-VMI-API-Key header. Only ReportSubmission exists.
#   "2"           - the body carries a top-level event_type (ReportSubmission or
#                   TransmissionComplete), and the api_key is only the HMAC
#                   secret for X-VMI-Signature; it is never sent.
class Transmitters::WebhookClient
  REPORT_SUBMISSION = "ReportSubmission".freeze
  TRANSMISSION_COMPLETE = "TransmissionComplete".freeze

  LEGACY_CONTRACT_VERSION = "1".freeze
  EVENTS_CONTRACT_VERSION = "2".freeze
  CONTRACT_VERSIONS = [ LEGACY_CONTRACT_VERSION, EVENTS_CONTRACT_VERSION ].freeze

  def initialize(transmission_config)
    @transmission_config = transmission_config.with_indifferent_access
  end

  def events_contract?
    @transmission_config["contract_version"].to_s == EVENTS_CONTRACT_VERSION
  end

  def post_event(event_type:, confirmation_code:, payload:)
    if event_type != REPORT_SUBMISSION && !events_contract?
      raise ArgumentError, "#{event_type} requires webhook contract_version #{EVENTS_CONTRACT_VERSION}"
    end

    webhook_url = URI(@transmission_config["webhook_url"])
    api_key = @transmission_config["api_key"]

    req = Net::HTTP::Post.new(webhook_url)
    req.content_type = "application/json"
    req.body = (events_contract? ? { event_type: event_type }.merge(payload) : payload).to_json

    timestamp = Time.now.to_i.to_s
    req["X-VMI-Timestamp"] = timestamp
    req["X-VMI-Signature"] = JsonApiSignature.generate(req.body, timestamp, api_key)
    req["X-VMI-API-Key"] = api_key unless events_contract?
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
      raise "Unexpected response from agency: #{res.code} #{res.message}"
    end
  end
end
