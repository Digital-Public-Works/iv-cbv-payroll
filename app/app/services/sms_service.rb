# Thin wrapper around the Twilio REST client. Credentials come from the
# TWILIO_* environment variables (SSM-sourced in deployed environments).
#
# Errors are classified for retry behavior: a PermanentDeliveryError will
# never succeed on retry (invalid number, opt-out), so callers should record
# the failure and stop; any other DeliveryError is worth retrying.
class SmsService
  PERMANENT_ERROR_CODES = [
    21211, # 'To' number is not a valid phone number
    21408, # Permission to send to this region is not enabled
    21610  # Recipient has opted out of messages from this sender
  ].freeze

  class DeliveryError < StandardError
    attr_reader :error_code

    def initialize(message, error_code: nil)
      @error_code = error_code
      super(message)
    end
  end

  class PermanentDeliveryError < DeliveryError; end

  def send_message(to:, body:)
    client.messages.create(
      messaging_service_sid: ENV.fetch("TWILIO_MESSAGING_SERVICE_SID"),
      to: to,
      body: body
    )
  rescue Twilio::REST::RestError => e
    error_class = PERMANENT_ERROR_CODES.include?(e.code) ? PermanentDeliveryError : DeliveryError
    raise error_class.new("Twilio error #{e.code}: #{e.message}", error_code: e.code)
  end

  private

  def client
    @client ||= Twilio::REST::Client.new(
      ENV.fetch("TWILIO_ACCOUNT_SID"),
      ENV.fetch("TWILIO_AUTH_TOKEN")
    )
  end
end
