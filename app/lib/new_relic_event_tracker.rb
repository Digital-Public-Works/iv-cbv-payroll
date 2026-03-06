class NewRelicEventTracker
  def initialize(client: nil)
    @client = client || NewRelic::EventApiClient.new
  end

  def track(event_type, attributes = {})
    start_time = Time.current
    Rails.logger.info "Sending NewRelic event #{event_type} with attributes: #{attributes}"

    response = @client.send_event(event_type, attributes)

    if response.success?
      Rails.logger.info "NewRelic event sent in #{Time.current - start_time}"
    end

    response
  rescue => e
    Rails.logger.error " Failed to track NewRelic #{event_type}: #{e.message}"
    raise e
  end
end
