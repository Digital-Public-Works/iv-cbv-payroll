require "rails_helper"

RSpec.describe SmsService, type: :service do
  let(:service) { described_class.new }
  let(:messages) { instance_double(Twilio::REST::Api::V2010::AccountContext::MessageList) }
  let(:client) { instance_double(Twilio::REST::Client, messages: messages) }

  before do
    stub_const("ENV", ENV.to_h.merge(
      "TWILIO_ACCOUNT_SID" => "ACtest",
      "TWILIO_AUTH_TOKEN" => "token",
      "TWILIO_MESSAGING_SERVICE_SID" => "MGtest"
    ))
    allow(Twilio::REST::Client).to receive(:new).with("ACtest", "token").and_return(client)
  end

  def twilio_error(code)
    response = Twilio::Response.new(400, { "code" => code, "message" => "Twilio says no" }.to_json)
    Twilio::REST::RestError.new("boom", response)
  end

  it "sends through the configured messaging service" do
    message = instance_double(Twilio::REST::Api::V2010::AccountContext::MessageInstance, sid: "SMtest")
    allow(messages).to receive(:create).and_return(message)

    expect(service.send_message(to: "+15552345678", body: "hello")).to eq(message)
    expect(messages).to have_received(:create).with(
      messaging_service_sid: "MGtest",
      to: "+15552345678",
      body: "hello"
    )
  end

  it "raises PermanentDeliveryError for non-retryable Twilio codes" do
    described_class::PERMANENT_ERROR_CODES.each do |code|
      allow(messages).to receive(:create).and_raise(twilio_error(code))

      expect { service.send_message(to: "+15552345678", body: "hello") }
        .to raise_error(described_class::PermanentDeliveryError) { |error|
          expect(error.error_code).to eq(code)
        }
    end
  end

  it "falls back to a from-number when no messaging service is configured" do
    stub_const("ENV", ENV.to_h.merge(
      "TWILIO_ACCOUNT_SID" => "ACtest",
      "TWILIO_AUTH_TOKEN" => "token",
      "TWILIO_MESSAGING_SERVICE_SID" => "",
      "TWILIO_FROM_NUMBER" => "+15005550006"
    ))
    message = instance_double(Twilio::REST::Api::V2010::AccountContext::MessageInstance, sid: "SMtest")
    allow(messages).to receive(:create).and_return(message)

    service.send_message(to: "+15552345678", body: "hello")

    expect(messages).to have_received(:create).with(
      from: "+15005550006",
      to: "+15552345678",
      body: "hello"
    )
  end

  it "raises when neither sender configuration is present" do
    stub_const("ENV", ENV.to_h.merge(
      "TWILIO_ACCOUNT_SID" => "ACtest",
      "TWILIO_AUTH_TOKEN" => "token",
      "TWILIO_MESSAGING_SERVICE_SID" => "",
      "TWILIO_FROM_NUMBER" => ""
    ))

    expect { service.send_message(to: "+15552345678", body: "hello") }
      .to raise_error(KeyError, /TWILIO_MESSAGING_SERVICE_SID or TWILIO_FROM_NUMBER/)
  end

  it "raises a retryable DeliveryError for other Twilio codes" do
    allow(messages).to receive(:create).and_raise(twilio_error(20429))

    expect { service.send_message(to: "+15552345678", body: "hello") }
      .to raise_error(described_class::DeliveryError) { |error|
        expect(error).not_to be_a(described_class::PermanentDeliveryError)
        expect(error.error_code).to eq(20429)
      }
  end
end
