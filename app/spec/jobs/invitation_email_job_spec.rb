require "rails_helper"

RSpec.describe InvitationEmailJob, type: :job do
  let(:invitation) { create(:cbv_flow_invitation, :sandbox) }
  let(:communication) { create(:invitation_communication, cbv_flow_invitation: invitation, channel: :email) }

  before do
    allow(NewRelic::Agent).to receive(:record_custom_event)
  end

  describe "#perform" do
    it "delivers the invitation email and marks the communication sent" do
      expect do
        described_class.perform_now(communication.id)
      end.to change { ActionMailer::Base.deliveries.count }.by(1)

      email = ActionMailer::Base.deliveries.last
      expect(email.to).to include(invitation.email_address)

      communication.reload
      expect(communication.status).to eq("sent")
      expect(communication.provider_message_id).to be_present
      expect(communication.sent_at).to be_present
    end

    it "renders in the invitation's language" do
      spanish_invitation = create(:cbv_flow_invitation, :sandbox, language: "es")
      spanish_communication = create(:invitation_communication, cbv_flow_invitation: spanish_invitation, channel: :email)

      described_class.perform_now(spanish_communication.id)

      email = ActionMailer::Base.deliveries.last
      expect(email.subject).to include("Verifique sus ingresos")
    end

    it "is idempotent for already-sent communications" do
      communication.update!(status: :sent, provider_message_id: "abc")

      expect do
        described_class.perform_now(communication.id)
      end.not_to change { ActionMailer::Base.deliveries.count }
    end

    context "when delivery fails" do
      before do
        allow(ApplicantMailer).to receive(:with).and_raise(
          StandardError.new("SES rejected recipient applicant@example.com")
        )
      end

      it "marks the communication failed with a scrubbed error and re-raises" do
        expect { described_class.perform_now(communication.id) }
          .to raise_error(StandardError, /SES rejected/)

        communication.reload
        expect(communication.status).to eq("failed")
        expect(communication.last_error).not_to include("applicant@example.com")
        expect(communication.last_error).to include("[email redacted]")
      end

      it "records a New Relic failure event" do
        described_class.perform_now(communication.id) rescue nil

        expect(NewRelic::Agent).to have_received(:record_custom_event).with(
          "EmailSendFailed",
          hash_including(invitation_communication_id: communication.id, error_class: "StandardError")
        )
      end

      it "recovers on a later redelivery" do
        described_class.perform_now(communication.id) rescue nil
        expect(communication.reload.status).to eq("failed")

        allow(ApplicantMailer).to receive(:with).and_call_original
        described_class.perform_now(communication.id)

        expect(communication.reload.status).to eq("sent")
      end
    end
  end

  it "enqueues on the email_sender queue" do
    expect(described_class.new.queue_name).to eq("email_sender")
  end
end
