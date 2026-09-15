require "rails_helper"

RSpec.describe SmsService, type: :service do
  let(:service) { described_class.new }
  let(:client) { instance_double(Aws::SNS::Client) }

  before do
    stub_const("ENV", ENV.to_h.merge(
      "AWS_REGION" => "us-east-1",
      "AWS_SNS_REGION" => "",
      "AWS_SNS_ACCESS_KEY_ID" => "",
      "AWS_SNS_SECRET_ACCESS_KEY" => "",
      "AWS_SNS_ENDPOINT" => "",
      "AWS_SNS_ORIGINATION_NUMBER" => "",
      "AWS_SNS_PROFILE" => ""
    ))
    allow(Aws::SNS::Client).to receive(:new).and_return(client)
  end

  # The SDK builds these classes from the wire code, so error#code round-trips.
  def sns_error(code)
    Aws::SNS::Errors.error_class(code).new(Seahorse::Client::RequestContext.new, "SNS says no")
  end

  def sns_error_with_message(code, message)
    Aws::SNS::Errors.error_class(code).new(Seahorse::Client::RequestContext.new, message)
  end

  def publish_response(message_id)
    instance_double(Aws::SNS::Types::PublishResponse, message_id: message_id)
  end

  it "publishes to the phone number and returns the message id" do
    allow(client).to receive(:publish).and_return(publish_response("sns-message-id"))

    expect(service.send_message(to: "+15552345678", body: "hello")).to eq("sns-message-id")
    expect(client).to have_received(:publish).with(
      phone_number: "+15552345678",
      message: "hello",
      message_attributes: {
        "AWS.SNS.SMS.SMSType" => { data_type: "String", string_value: "Transactional" }
      }
    )
  end

  it "includes an origination number when one is configured" do
    stub_const("ENV", ENV.to_h.merge("AWS_SNS_ORIGINATION_NUMBER" => "+15005550006"))
    allow(client).to receive(:publish).and_return(publish_response("sns-message-id"))

    service.send_message(to: "+15552345678", body: "hello")

    expect(client).to have_received(:publish).with(
      hash_including(message_attributes: hash_including(
        "AWS.MM.SMS.OriginationNumber" => { data_type: "String", string_value: "+15005550006" }
      ))
    )
  end

  it "raises PermanentDeliveryError for non-retryable SNS codes" do
    described_class::PERMANENT_ERROR_CODES.each do |code|
      allow(client).to receive(:publish).and_raise(sns_error(code))

      expect { service.send_message(to: "+15552345678", body: "hello") }
        .to raise_error(described_class::PermanentDeliveryError) { |error|
          expect(error.error_code).to eq(code)
        }
    end
  end

  # The raised message reaches worker logs and the exception tracker on transient
  # failures, so the number must already be gone by the time it is raised.
  it "scrubs the recipient's number out of the error it raises" do
    allow(client).to receive(:publish).and_raise(
      sns_error_with_message("InvalidParameter", "Invalid parameter: PhoneNumber Reason: +15552345678 is not verified")
    )

    expect { service.send_message(to: "+15552345678", body: "hello") }
      .to raise_error(described_class::PermanentDeliveryError) { |error|
        expect(error.message).not_to include("5552345678")
        expect(error.message).to include("[phone redacted]")
        expect(error.message).to include("InvalidParameter")
      }
  end

  it "scrubs the recipient's number out of networking errors too" do
    allow(client).to receive(:publish).and_raise(
      Seahorse::Client::NetworkingError.new(StandardError.new("failed sending to +15552345678"))
    )

    expect { service.send_message(to: "+15552345678", body: "hello") }
      .to raise_error(described_class::DeliveryError) { |error|
        expect(error.message).not_to include("5552345678")
      }
  end

  # U+202C and friends ride along when a number is pasted from a console or the
  # AWS UI; SNS reports them as a generic unverified-number error.
  it "strips invisible formatting characters before publishing" do
    allow(client).to receive(:publish).and_return(publish_response("sns-message-id"))

    service.send_message(to: "+15552345678\u202C", body: "hello")

    expect(client).to have_received(:publish).with(hash_including(phone_number: "+15552345678"))
  end

  it "rejects a destination that is not E.164 with an actionable error" do
    allow(client).to receive(:publish)

    expect { service.send_message(to: "555-234-5678", body: "hello") }
      .to raise_error(described_class::PermanentDeliveryError, /not E\.164/) { |error|
        expect(error.error_code).to eq("InvalidDestination")
      }
    expect(client).not_to have_received(:publish)
  end

  it "raises a retryable DeliveryError for other SNS codes" do
    allow(client).to receive(:publish).and_raise(sns_error("Throttled"))

    expect { service.send_message(to: "+15552345678", body: "hello") }
      .to raise_error(described_class::DeliveryError) { |error|
        expect(error).not_to be_a(described_class::PermanentDeliveryError)
        expect(error.error_code).to eq("Throttled")
      }
  end

  it "raises a retryable DeliveryError when the network fails" do
    allow(client).to receive(:publish)
      .and_raise(Seahorse::Client::NetworkingError.new(StandardError.new("connection reset")))

    expect { service.send_message(to: "+15552345678", body: "hello") }
      .to raise_error(described_class::DeliveryError) { |error|
        expect(error).not_to be_a(described_class::PermanentDeliveryError)
        expect(error.error_code).to eq("NetworkingError")
      }
  end

  # aws-sdk-rails points Aws.config[:logger] at the Rails logger, and the SDK's
  # default formatter inspects request params. The SMS body is an auth-token
  # magic link, so this exercises a real client end to end rather than asserting
  # on the option, and proves nothing sensitive reaches the log.
  describe "SDK request logging" do
    it "keeps the message body and recipient out of the logs" do
      allow(Aws::SNS::Client).to receive(:new).and_call_original
      log = StringIO.new
      service = described_class.new
      allow(service).to receive(:client_options)
        .and_return(service.send(:client_options).merge(
          stub_responses: true,
          access_key_id: "test",
          secret_access_key: "test",
          logger: ActiveSupport::Logger.new(log)
        ))

      service.send_message(to: "+15552345678", body: "Verify your income: https://example.gov/i/SECRETTOKEN")

      expect(log.string).not_to include("SECRETTOKEN")
      expect(log.string).not_to include("5552345678")
      expect(log.string).to include("publish")
    end
  end

  describe "client configuration" do
    before { allow(client).to receive(:publish).and_return(publish_response("sns-message-id")) }

    it "defaults to the ambient AWS region and credential chain" do
      service.send_message(to: "+15552345678", body: "hello")

      expect(Aws::SNS::Client).to have_received(:new)
        .with(hash_including(region: "us-east-1"))
    end

    it "uses an SSO profile when one is named" do
      stub_const("ENV", ENV.to_h.merge("AWS_SNS_PROFILE" => "demo"))

      service.send_message(to: "+15552345678", body: "hello")

      expect(Aws::SNS::Client).to have_received(:new).with(hash_including(profile: "demo"))
    end

    # The tracked .env ships AWS_SNS_PROFILE=[POPULATE THIS]; a leftover key
    # placeholder must not quietly shadow a profile the developer actually set.
    it "prefers the profile over static keys when both are present" do
      stub_const("ENV", ENV.to_h.merge(
        "AWS_SNS_PROFILE" => "demo",
        "AWS_SNS_ACCESS_KEY_ID" => "AKIAtest",
        "AWS_SNS_SECRET_ACCESS_KEY" => "secret"
      ))

      service.send_message(to: "+15552345678", body: "hello")

      expect(Aws::SNS::Client).to have_received(:new).with(hash_including(profile: "demo"))
      expect(Aws::SNS::Client).not_to have_received(:new).with(hash_including(:access_key_id))
    end

    # Locally the ambient AWS_* credentials point at Moto, so SNS needs its own.
    it "uses the AWS_SNS_* overrides when they are set" do
      stub_const("ENV", ENV.to_h.merge(
        "AWS_SNS_REGION" => "us-west-2",
        "AWS_SNS_ACCESS_KEY_ID" => "AKIAtest",
        "AWS_SNS_SECRET_ACCESS_KEY" => "secret",
        "AWS_SNS_ENDPOINT" => "http://localhost:3456"
      ))

      service.send_message(to: "+15552345678", body: "hello")

      expect(Aws::SNS::Client).to have_received(:new).with(hash_including(
        region: "us-west-2",
        access_key_id: "AKIAtest",
        secret_access_key: "secret",
        endpoint: "http://localhost:3456"
      ))
    end
  end
end
