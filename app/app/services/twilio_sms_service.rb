# CURRENTLY UNUSED. Invitation SMS goes out through AWS SNS (see SmsService);
# this class is retained, loadable, and under test in case we move back to
# Twilio, which offers per-message delivery callbacks and synchronous opt-out
# reporting that SNS does not. To re-enable, point InvitationSmsJob#sms_service
# at this class and restore the TWILIO_* environment variables.
#
# Thin wrapper around the Twilio REST client. Credentials come from the
# TWILIO_* environment variables (SSM-sourced in deployed environments).
#
# #send_message returns the provider's message id as a String, and it raises
# SmsService's error classes, so the two providers are interchangeable to
# callers. A PermanentDeliveryError will never succeed on retry (invalid
# number, opt-out); any other DeliveryError is worth retrying.
class TwilioSmsService
  PERMANENT_ERROR_CODES = [
    21211,  # 'To' number is not a valid phone number
    21408,  # Permission to send to this region is not enabled
    21610,  # Recipient has opted out of messages from this sender
    572006  # Trial accounts can only send predefined templates, never our body
  ].freeze

  def send_message(to:, body:)
    client.messages.create(**sender_params, to: to, body: body).sid
  rescue Twilio::REST::RestError => e
    permanent = PERMANENT_ERROR_CODES.include?(e.code)
    error_class = permanent ? SmsService::PermanentDeliveryError : SmsService::DeliveryError
    raise error_class.new(
      "Twilio error #{e.code}: #{SmsService.scrub_phone_numbers(e.message)}",
      error_code: e.code
    )
  end

  private

  # Prefer a Messaging Service (production: pooled senders, per-number
  # compliance handled by Twilio); fall back to a single from-number, which is
  # all a trial account has.
  def sender_params
    if ENV["TWILIO_MESSAGING_SERVICE_SID"].present?
      { messaging_service_sid: ENV["TWILIO_MESSAGING_SERVICE_SID"] }
    elsif ENV["TWILIO_FROM_NUMBER"].present?
      { from: ENV["TWILIO_FROM_NUMBER"] }
    else
      raise KeyError.new("Set TWILIO_MESSAGING_SERVICE_SID or TWILIO_FROM_NUMBER")
    end
  end

  def client
    @client ||= Twilio::REST::Client.new(
      ENV.fetch("TWILIO_ACCOUNT_SID"),
      ENV.fetch("TWILIO_AUTH_TOKEN")
    )
  end
end
