# An applicant-facing send of an invitation over a communication channel
# (e.g. SMS), one row per send attempt. Distinct from CbvFlowTransmission,
# which is the agency-facing send of a completed income report.
class InvitationCommunication < ApplicationRecord
  belongs_to :cbv_flow_invitation

  enum :channel, {
    sms: "sms"                      # defines the method: channel_sms?
  }, prefix: "channel"

  enum :status, {
    created: "created",             # defines the method: status_created?
    sending: "sending",             # defines the method: status_sending?
    sent: "sent",                   # accepted by the provider; a valid resting state
    delivered: "delivered",         # confirmed by a provider delivery callback
    failed: "failed"                # terminal; see last_error
  }, prefix: "status"

  def terminal?
    status_delivered? || status_failed?
  end
end
