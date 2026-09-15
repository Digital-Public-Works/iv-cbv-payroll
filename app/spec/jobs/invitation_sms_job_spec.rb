require "rails_helper"

RSpec.describe InvitationSmsJob, type: :job do
  let(:invitation) { create(:cbv_flow_invitation, :sms, :sandbox) }
  let(:communication) { create(:invitation_communication, cbv_flow_invitation: invitation) }
  let(:sms_service) { instance_double(SmsService) }
  let(:provider_message_id) { "sns-message-id" }

  before do
    allow(SmsService).to receive(:new).and_return(sms_service)
    allow(NewRelic::Agent).to receive(:record_custom_event)
    # Real wait is 3s between the two messages; don't pay it in every example.
    allow_any_instance_of(described_class).to receive(:pause_between_messages)
  end

  describe "#perform" do
    it "sends the SMS and marks the communication sent" do
      allow(sms_service).to receive(:send_message).and_return(provider_message_id)

      described_class.perform_now(communication.id)

      # Assert on the contract (recipient, agency, working link) rather than the
      # wording, which partners revise without touching this job.
      expect(sms_service).to have_received(:send_message).with(
        to: invitation.phone_number,
        body: a_string_including(invitation.to_url)
      )

      communication.reload
      expect(communication.status).to eq("sent")
      expect(communication.provider_message_id).to eq(provider_message_id)
      expect(communication.sent_at).to be_present
    end

    it "waits between the two messages so they arrive in order" do
      allow(sms_service).to receive(:send_message).and_return(provider_message_id)
      job = described_class.new(communication.id)
      allow(job).to receive(:pause_between_messages).and_call_original
      allow(job).to receive(:sleep)

      job.perform_now

      expect(job).to have_received(:sleep).with(described_class::DEFAULT_INTER_MESSAGE_DELAY_SECONDS)
    end

    it "sends the opt-in notice before the invitation" do
      bodies = []
      allow(sms_service).to receive(:send_message) { |to:, body:| bodies << body; provider_message_id }

      described_class.perform_now(communication.id)

      expect(bodies.length).to eq(2)
      expect(bodies.first).to include("You have opted in")
      expect(bodies.first).to include("Reply HELP for help or STOP to cancel")
      # The notice promises a following message, so the link must not be in it.
      expect(bodies.first).not_to include(invitation.to_url)
      expect(bodies.last).to include(invitation.to_url)
    end

    it "sends the opt-in notice in English even for a Spanish invitation" do
      spanish = create(:cbv_flow_invitation, :sms, :sandbox, language: "es")
      spanish_communication = create(:invitation_communication, cbv_flow_invitation: spanish)
      bodies = []
      allow(sms_service).to receive(:send_message) { |to:, body:| bodies << body; provider_message_id }

      described_class.perform_now(spanish_communication.id)

      expect(bodies.first).to include("You have opted in")
    end

    it "does not send the invitation when the opt-in notice fails" do
      allow(sms_service).to receive(:send_message).and_raise(
        SmsService::PermanentDeliveryError.new("SNS error InvalidParameter", error_code: "InvalidParameter")
      )

      described_class.perform_now(communication.id)

      expect(sms_service).to have_received(:send_message).once
      expect(communication.reload.status).to eq("failed")
    end

    it "stores the invitation's message id, not the notice's" do
      allow(sms_service).to receive(:send_message).and_return("notice-id", "invitation-id")

      described_class.perform_now(communication.id)

      expect(communication.reload.provider_message_id).to eq("invitation-id")
    end

    it "includes the invitation link and renders in the invitation's language" do
      spanish_invitation = create(:cbv_flow_invitation, :sms, :sandbox, language: "es")
      spanish_communication = create(:invitation_communication, cbv_flow_invitation: spanish_invitation)

      bodies = []
      allow(sms_service).to receive(:send_message) do |to:, body:|
        expect(to).to eq(spanish_invitation.phone_number)
        bodies << body
        provider_message_id
      end

      described_class.perform_now(spanish_communication.id)

      # The invitation is the second message; the first is the English notice.
      expect(bodies.last).to include(spanish_invitation.auth_token)
      expect(bodies.last).to include("ingresos")
    end

    it "is idempotent for already-sent communications" do
      communication.update!(status: :sent, provider_message_id: provider_message_id)
      expect(sms_service).not_to receive(:send_message)

      described_class.perform_now(communication.id)
    end

    it "tracks an SmsSent event on success" do
      allow(sms_service).to receive(:send_message).and_return(provider_message_id)
      event_logger = instance_double(GenericEventTracker, track: nil)
      allow(GenericEventTracker).to receive(:new).and_return(event_logger)

      described_class.perform_now(communication.id)

      expect(event_logger).to have_received(:track).with(
        "SmsSent",
        nil,
        hash_including(invitation_communication_id: communication.id)
      )
    end

    context "on a permanent provider error" do
      before do
        allow(sms_service).to receive(:send_message).and_raise(
          SmsService::PermanentDeliveryError.new(
            "SNS error InvalidParameter: Invalid parameter: PhoneNumber +15552345678",
            error_code: "InvalidParameter"
          )
        )
      end

      it "marks the communication failed without re-raising" do
        expect { described_class.perform_now(communication.id) }.not_to raise_error

        communication.reload
        expect(communication.status).to eq("failed")
        expect(communication.last_error).to include("InvalidParameter")
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
            provider_error_code: "InvalidParameter"
          )
        )
      end
    end

    context "on a transient provider error" do
      before do
        allow(sms_service).to receive(:send_message).and_raise(
          SmsService::DeliveryError.new("SNS error Throttled: too many requests", error_code: "Throttled")
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

        allow(sms_service).to receive(:send_message).and_return(provider_message_id)
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
