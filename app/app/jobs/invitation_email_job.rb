# Sends one invitation email and records the outcome on its
# InvitationCommunication row. Enqueued by CbvInvitationService when the email
# communication channel is selected. Mirrors InvitationSmsJob: delivery
# failures mark the row failed and re-raise, so SQS redelivers and a later
# attempt can still transition it to sent.
class InvitationEmailJob < ApplicationJob
  queue_as { self.class.queue_with_suffix(:email_sender) }

  EMAIL_REGEX = /[^\s@]+@[^\s@]+/

  def perform(invitation_communication_id)
    communication = InvitationCommunication.find(invitation_communication_id)
    return if communication.status_sent? || communication.status_delivered?

    invitation = communication.cbv_flow_invitation
    communication.update!(status: :sending)

    mail = ApplicantMailer.with(cbv_flow_invitation: invitation).invitation_email
    mail.deliver_now

    communication.update!(
      status: :sent,
      provider_message_id: mail.message_id,
      sent_at: Time.current,
      last_error: nil
    )
    # TrackEvent::EmailSent is emitted by ApplicationMailer#track_delivery.
  rescue StandardError => e
    raise if communication.nil?

    record_failure(communication, e)
    raise
  end

  private

  def record_failure(communication, error)
    communication.update!(status: :failed, last_error: scrub_recipient(error.message))

    NewRelic::Agent.record_custom_event(TrackEvent::EmailSendFailed, {
      invitation_communication_id: communication.id,
      invitation_id: communication.cbv_flow_invitation_id,
      client_agency_id: communication.cbv_flow_invitation.client_agency_id,
      error_class: error.class.name,
      failed_at: Time.current.to_s
    })
  end

  # Mail errors can echo the recipient address; keep it out of the database.
  def scrub_recipient(message)
    message.to_s.gsub(EMAIL_REGEX, "[email redacted]")
  end
end
