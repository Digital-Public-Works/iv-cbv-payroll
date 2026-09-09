# Sends one invitation SMS and records the outcome on its
# InvitationCommunication row. Enqueued by CbvInvitationService when the sms
# communication channel is selected.
#
# Retry model: permanent Twilio errors (invalid number, opt-out) mark the
# communication failed and do NOT re-raise, so the message is not redelivered.
# Transient errors mark it failed and re-raise; SQS redelivers (up to the
# queue's maxReceiveCount) and a later success transitions the row to sent.
class InvitationSmsJob < ApplicationJob
  queue_as { self.class.queue_with_suffix(:sms_sender) }

  def perform(invitation_communication_id)
    communication = InvitationCommunication.find(invitation_communication_id)
    # Skip only if the message already went out. A failed row is retried:
    # transient failures re-raise so SQS redelivers this same job.
    return if communication.status_sent? || communication.status_delivered?

    invitation = communication.cbv_flow_invitation
    communication.update!(status: :sending)

    message = sms_service.send_message(
      to: invitation.phone_number,
      body: message_body(invitation)
    )

    communication.update!(
      status: :sent,
      twilio_message_sid: message.sid,
      sent_at: Time.current,
      last_error: nil
    )
    track_sms_sent(communication, invitation)
  rescue SmsService::PermanentDeliveryError => e
    record_failure(communication, e)
  rescue SmsService::DeliveryError => e
    record_failure(communication, e)
    raise
  end

  private

  def sms_service
    @sms_service ||= SmsService.new
  end

  def message_body(invitation)
    agency = ClientAgencyConfig.instance[invitation.client_agency_id]
    helpers = ApplicationController.helpers

    I18n.with_locale(invitation.language) do
      helpers.agency_translation_for(
        agency,
        "applicant_sms.invitation.body",
        agency_acronym: helpers.agency_acronym_or_full_name_for(agency),
        deadline: helpers.format_date(invitation.expires_at_local.to_s),
        link: invitation.to_url
      )
    end
  end

  def record_failure(communication, error)
    communication.update!(status: :failed, last_error: scrub_phone_numbers(error.message))

    NewRelic::Agent.record_custom_event(TrackEvent::SmsSendFailed, {
      invitation_communication_id: communication.id,
      invitation_id: communication.cbv_flow_invitation_id,
      client_agency_id: communication.cbv_flow_invitation.client_agency_id,
      twilio_error_code: error.error_code,
      error_class: error.class.name,
      failed_at: Time.current.to_s
    })
  end

  # Twilio error messages can echo the recipient's phone number; keep it out
  # of the database and anything downstream of last_error.
  def scrub_phone_numbers(message)
    message.to_s.gsub(/\+?\d{7,}/, "[phone redacted]")
  end

  def track_sms_sent(communication, invitation)
    event_logger.track(TrackEvent::SmsSent, nil, {
      time: Time.current.to_i,
      invitation_id: invitation.id,
      invitation_communication_id: communication.id,
      client_agency_id: invitation.client_agency_id,
      locale: invitation.language
    })
  end
end
