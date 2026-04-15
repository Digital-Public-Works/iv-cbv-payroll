class Transmitters::SharedEmailTransmitter
  include Transmitter

  def deliver
    CaseworkerMailer.with(
      email_address: @transmission_config.dig("email"),
      cbv_flow: @cbv_flow,
      aggregator_report: @aggregator_report,
    ).summary_email.deliver_now
  end
end
