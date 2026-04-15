class Transmitters::WebhookTransmitter
  include Transmitter

  def deliver
    webhook_url = URI(@transmission_config["webhook_url"])
    api_key = @transmission_config["api_key"]

    req = Net::HTTP::Post.new(webhook_url)
    req.content_type = "application/json"
    req.body = CbvFlowToJson.new(@cbv_flow, @current_agency, @aggregator_report).to_h.to_json

    timestamp = Time.now.to_i.to_s
    req["X-VMI-Timestamp"] = timestamp
    req["X-VMI-Signature"] = JsonApiSignature.generate(req.body, timestamp, api_key)
    req["X-VMI-API-Key"] = api_key
    req["X-VMI-Confirmation-Code"] = @cbv_flow.confirmation_code

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
