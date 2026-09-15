require "aws-sdk-sns"

# Thin wrapper around AWS SNS for sending invitation SMS. Credentials come from
# the standard AWS chain (a task role in deployed environments), with optional
# AWS_SNS_* overrides so local development can point SNS at real AWS while SQS
# stays on Moto -- see .env for the full list.
#
# #send_message returns the provider's message id as a String. Errors are
# classified for retry behavior: a PermanentDeliveryError will never succeed on
# retry (unroutable number, unverified sandbox destination), so callers should
# record the failure and stop; any other DeliveryError is worth retrying.
#
# TwilioSmsService speaks the same contract and raises these same error classes;
# it is retained but unused.
class SmsService
  # Codes that no retry can fix. SNS reports most per-recipient problems as
  # InvalidParameter ("Invalid parameter: PhoneNumber ..."). Everything else --
  # throttling, InternalError, AuthorizationError, network failures -- is left
  # retryable so a misconfiguration surfaces loudly instead of silently
  # swallowing every send.
  #
  # Compared with any trailing "Exception" stripped: SNS returns some codes bare
  # ("InvalidParameter") and others suffixed ("ValidationException").
  PERMANENT_ERROR_CODES = [
    "InvalidParameter",       # malformed or unroutable destination number
    "InvalidParameterValue",
    "ParameterValueInvalid",
    "ValidationException",
    "VerificationException",  # destination not verified while in the SMS sandbox
    "OptedOutException"       # recipient opted out of messages from this sender
  ].freeze

  # Invitations are one-time passcodes in spirit: prefer reliability over cost.
  SMS_TYPE = "Transactional".freeze

  # Provider error text echoes the recipient's number -- SNS names it outright in
  # "Invalid parameter: PhoneNumber Reason: +15551234567 ...". Scrubbed at the
  # point the text enters our system rather than only where it is stored, so the
  # number cannot reach a log, an exception tracker, or the database no matter
  # who ends up handling the error.
  PHONE_NUMBER_PATTERN = /\+?\d{7,}/

  def self.scrub_phone_numbers(text)
    text.to_s.gsub(PHONE_NUMBER_PATTERN, "[phone redacted]")
  end

  class DeliveryError < StandardError
    attr_reader :error_code

    def initialize(message, error_code: nil)
      @error_code = error_code
      super(message)
    end
  end

  class PermanentDeliveryError < DeliveryError; end

  def send_message(to:, body:)
    response = client.publish(
      phone_number: normalize_destination(to),
      message: body,
      message_attributes: message_attributes
    )
    response.message_id
  rescue Aws::SNS::Errors::ServiceError => e
    error_class = permanent?(e.code) ? PermanentDeliveryError : DeliveryError
    raise error_class.new(
      "SNS error #{e.code}: #{self.class.scrub_phone_numbers(e.message)}",
      error_code: e.code
    )
  rescue Seahorse::Client::NetworkingError => e
    raise DeliveryError.new(
      "SNS networking error: #{self.class.scrub_phone_numbers(e.message)}",
      error_code: "NetworkingError"
    )
  end

  private

  # Numbers pasted from a console, browser, or the AWS UI often carry invisible
  # Unicode formatting characters (U+202C and friends). SNS rejects those with a
  # generic "PhoneNumber ... is not valid to publish to", which reads as an
  # account or verification problem rather than a bad string -- so fail here
  # instead, with a message that says what is actually wrong. Records a permanent
  # failure: no retry can fix the input.
  def normalize_destination(to)
    cleaned = to.to_s.gsub(/[[:space:]]|\p{Cf}/, "")
    return cleaned if cleaned.match?(/\A\+[1-9]\d{6,14}\z/)

    raise PermanentDeliveryError.new(
      "Destination is not E.164 (#{cleaned.length} characters after removing " \
      "whitespace and invisible formatting). Expected +<country><number>.",
      error_code: "InvalidDestination"
    )
  end

  def permanent?(code)
    normalized = strip_exception_suffix(code)
    PERMANENT_ERROR_CODES.any? { |permanent| strip_exception_suffix(permanent) == normalized }
  end

  def strip_exception_suffix(code)
    code.to_s.sub(/Exception\z/, "")
  end

  # An explicit origination number pins sends to one registered long code or
  # short code. Without it SNS picks from whatever the account has registered,
  # which is all a sandbox account needs.
  def message_attributes
    attributes = {
      "AWS.SNS.SMS.SMSType" => { data_type: "String", string_value: SMS_TYPE }
    }

    if ENV["AWS_SNS_ORIGINATION_NUMBER"].present?
      attributes["AWS.MM.SMS.OriginationNumber"] = {
        data_type: "String",
        string_value: ENV["AWS_SNS_ORIGINATION_NUMBER"]
      }
    end

    attributes
  end

  def client
    @client ||= Aws::SNS::Client.new(client_options)
  end

  def client_options
    options = {
      region: ENV["AWS_SNS_REGION"].presence || ENV.fetch("AWS_REGION", "us-east-1"),
      # aws-sdk-rails points Aws.config[:logger] at the Rails logger, and the SDK's
      # default formatter inspects request params -- which here means the message
      # body, i.e. the invitation's auth-token magic link, written to the log in
      # plaintext on every successful send. The short formatter keeps the useful
      # part (operation, status, latency) and drops the params.
      log_formatter: Aws::Log::Formatter.short
    }

    # Both of these exist only for local development, where the ambient
    # AWS_ACCESS_KEY_ID is a Moto placeholder that would otherwise be picked up;
    # deployed environments set neither and use the task role.
    #
    # A profile is the preferred local option -- it resolves through SSO, so
    # there is no long-lived key on the machine (see
    # docs/infra/set-up-infrastructure-tools.md). Passing :profile also overrides
    # AWS_SDK_LOAD_CONFIG=false, which is why an SSO profile works here at all.
    # It wins over static keys so a leftover placeholder in the tracked .env
    # cannot silently shadow a working profile.
    access_key = ENV["AWS_SNS_ACCESS_KEY_ID"]
    secret_key = ENV["AWS_SNS_SECRET_ACCESS_KEY"]
    if ENV["AWS_SNS_PROFILE"].present?
      options[:profile] = ENV["AWS_SNS_PROFILE"]
    elsif access_key.present? && secret_key.present?
      options[:access_key_id] = access_key
      options[:secret_access_key] = secret_key
    end

    options[:endpoint] = ENV["AWS_SNS_ENDPOINT"] if ENV["AWS_SNS_ENDPOINT"].present?
    options
  end
end
