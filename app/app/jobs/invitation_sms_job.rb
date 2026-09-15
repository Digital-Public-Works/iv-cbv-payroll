# Sends the invitation over SMS and records the outcome on its
# InvitationCommunication row. Enqueued by CbvInvitationService when the sms
# communication channel is selected.
#
# Two messages go out per send, in order: a 10DLC opt-in confirmation, then the
# invitation itself. A failure on the first aborts before the invitation is sent
# -- a bad number fails both, and delivering the link without the notice is the
# compliance gap the notice exists to close.
#
# PROTOTYPE LIMITATION: both messages share one InvitationCommunication row, so
# provider_message_id holds the invitation's id only, an opt-in failure is not
# distinguishable from an invitation failure, and an SQS redelivery after the
# opt-in succeeded but the invitation failed re-sends the opt-in. Production
# needs one row per message (a `kind` column); see
# docs/adr/0003-aws-sns-for-invitation-sms.md.
#
# Retry model: permanent provider errors (unroutable number, unverified
# sandbox destination) mark the communication failed and do NOT re-raise, so
# the message is not redelivered.
# Transient errors mark it failed and re-raise; SQS redelivers (up to the
# queue's maxReceiveCount) and a later success transitions the row to sent.
class InvitationSmsJob < ApplicationJob
  queue_as { self.class.queue_with_suffix(:sms_sender) }

  # SNS accepts the two publishes in order, but ordering is not guaranteed end to
  # end, and the gap is wider than it looks: the notice is two segments and the
  # invitation is one, so the notice is not displayed until the handset has both
  # parts and reassembles them, while the invitation displays on arrival. 3s was
  # measured to be too short in practice. The durable fix is a notice under 160
  # characters (one segment); until then, wait longer. 0 disables the wait.
  DEFAULT_INTER_MESSAGE_DELAY_SECONDS = 5.0

  def perform(invitation_communication_id)
    communication = InvitationCommunication.find(invitation_communication_id)
    # Skip only if the message already went out. A failed row is retried:
    # transient failures re-raise so SQS redelivers this same job.
    return if communication.status_sent? || communication.status_delivered?

    invitation = communication.cbv_flow_invitation
    communication.update!(status: :sending)

    # Order matters: the notice tells the applicant to expect the next message.
    # Raising here skips the invitation entirely, which is intended.
    sms_service.send_message(
      to: invitation.phone_number,
      body: consent_notice_body(invitation)
    )
    pause_between_messages

    message_id = sms_service.send_message(
      to: invitation.phone_number,
      body: message_body(invitation)
    )

    communication.update!(
      status: :sent,
      provider_message_id: message_id,
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

  # Blocks this worker thread briefly. Acceptable at invitation volumes; if that
  # ever stops being true, the two messages need to become two jobs.
  def pause_between_messages
    seconds = ENV.fetch("SMS_INTER_MESSAGE_DELAY_SECONDS", DEFAULT_INTER_MESSAGE_DELAY_SECONDS).to_f
    sleep(seconds) if seconds.positive?
  end

  # Not agency-branded: Digital Public Works is the sending party of record for
  # 10DLC purposes, so this copy is fixed rather than per-partner.
  def consent_notice_body(invitation)
    agency = ClientAgencyConfig.instance[invitation.client_agency_id]

    I18n.with_locale(invitation.language) do
      ApplicationController.helpers.agency_translation_for(agency, "applicant_sms.consent_notice.body")
    end
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
      provider_error_code: error.error_code,
      error_class: error.class.name,
      failed_at: Time.current.to_s
    })
  end

  def scrub_phone_numbers(message)
    SmsService.scrub_phone_numbers(message)
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
