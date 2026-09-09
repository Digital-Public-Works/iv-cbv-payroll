require "rails_helper"

RSpec.describe InvitationSmsJob, type: :job do
  let(:invitation) { create(:cbv_flow_invitation, :sms, :sandbox) }
  let(:communication) { create(:invitation_communication, cbv_flow_invitation: invitation) }
  let(:sms_service) { instance_double(SmsService) }
  let(:twilio_message) { instance_double(Twilio::REST::Api::V2010::AccountContext::MessageInstance, sid: "SM123") }

  before do
    allow(SmsService).to receive(:new).and_return(sms_service)
    allow(NewRelic::Agent).to receive(:record_custom_event)
  end

  describe "#perform" do
    it "sends the SMS and marks the communication sent" do
      allow(sms_service).to receive(:send_message).and_return(twilio_message)

      described_class.perform_now(communication.id)

      expect(sms_service).to have_received(:send_message)
        .with(to: invitation.phone_number, body: /verify your income/)

      communication.reload
      expect(communication.status).to eq("sent")
      expect(communication.twilio_message_sid).to eq("SM123")
      expect(communication.sent_at).to be_present
    end

    it "includes the invitation link and renders in the invitation's language" do
      spanish_invitation = create(:cbv_flow_invitation, :sms, :sandbox, language: "es")
      spanish_communication = create(:invitation_communication, cbv_flow_invitation: spanish_invitation)

      expect(sms_service).to receive(:send_message) do |to:, body:|
        expect(to).to eq(spanish_invitation.phone_number)
        expect(body).to include(spanish_invitation.auth_token)
        expect(body).to include("verificar sus ingresos")
        twilio_message
      end

      described_class.perform_now(spanish_communication.id)
    end

    it "is idempotent for already-sent communications" do
      communication.update!(status: :sent, twilio_message_sid: "SM123")
      expect(sms_service).not_to receive(:send_message)

      described_class.perform_now(communication.id)
    end

    it "tracks an SmsSent event on success" do
      allow(sms_service).to receive(:send_message).and_return(twilio_message)
      event_logger = instance_double(GenericEventTracker, track: nil)
      allow(GenericEventTracker).to receive(:new).and_return(event_logger)

      described_class.perform_now(communication.id)

      expect(event_logger).to have_received(:track).with(
        "SmsSent",
        nil,
        hash_including(invitation_communication_id: communication.id)
      )
    end

    context "on a permanent Twilio error" do
      before do
        allow(sms_service).to receive(:send_message).and_raise(
          SmsService::PermanentDeliveryError.new("Twilio error 21211: number +15552345678 is invalid", error_code: 21211)
        )
      end

      it "marks the communication failed without re-raising" do
        expect { described_class.perform_now(communication.id) }.not_to raise_error

        communication.reload
        expect(communication.status).to eq("failed")
        expect(communication.last_error).to include("21211")
      end

      it "scrubs phone numbers from the stored error" do
        described_class.perform_now(communication.id)

        expect(communication.reload.last_error).not_to include("5552345678")
        expect(communication.last_error).to include("[phone redacted]")
      end

      it "records a New Relic failure event without PII" do
        described_class.perform_now(communication.id)

        expect(NewRelic::Agent).to have_received(:record_custom_event).with(
          "SmsSendFailed",
          hash_including(
            invitation_communication_id: communication.id,
            twilio_error_code: 21211
          )
        )
      end
    end

    context "on a transient Twilio error" do
      before do
        allow(sms_service).to receive(:send_message).and_raise(
          SmsService::DeliveryError.new("Twilio error 20429: too many requests", error_code: 20429)
        )
      end

      it "marks the communication failed and re-raises for redelivery" do
        expect { described_class.perform_now(communication.id) }
          .to raise_error(SmsService::DeliveryError)

        expect(communication.reload.status).to eq("failed")
      end

      it "recovers on a later redelivery" do
        described_class.perform_now(communication.id) rescue nil
        expect(communication.reload.status).to eq("failed")

        allow(sms_service).to receive(:send_message).and_return(twilio_message)
        described_class.perform_now(communication.id)

        communication.reload
        expect(communication.status).to eq("sent")
        expect(communication.last_error).to be_nil
      end
    end
  end

  it "enqueues on the sms_sender queue" do
    expect(described_class.new.queue_name).to eq("sms_sender")
  end
end
