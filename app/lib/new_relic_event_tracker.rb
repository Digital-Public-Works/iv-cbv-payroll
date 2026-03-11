class NewRelicEventTracker
  def initialize(client: nil)
    @client = client || NewRelic::EventApiClient.new
  end

  def track(event_type, attributes = {})
    start_time = Time.current
    Rails.logger.info "Sending NewRelic event #{event_type} with attributes: #{attributes}"

    response = @client.send_event(event_type, attributes)
    code = response.status.to_i

    if response.success?
      Rails.logger.info "NewRelic event sent in #{Time.current - start_time}"
    else
      case code
      when 408, 429, 500, 503
        raise "Retryable NewRelic API error: #{code}"
      when 400, 403, 413, 415
        Rails.logger.error "NewRelic API error: #{code}. Check content or license key."
      else
        raise "Unknown NewRelic API error: #{code}"
      end
    end

    response
  rescue => e
    Rails.logger.error "Failed to track NewRelic #{event_type}: #{e.message}"
    raise e
  end
end
