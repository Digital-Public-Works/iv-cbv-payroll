class Transmitters::WebhookTransmitter
  include Transmitter

  def deliver
    Transmitters::WebhookClient.new(@transmission_config).post_event(
      event_type: Transmitters::WebhookClient::REPORT_SUBMISSION,
      confirmation_code: @cbv_flow.confirmation_code,
      payload: CbvFlowToJson.new(@cbv_flow, @current_agency, @aggregator_report).to_h
    )
  end
end
