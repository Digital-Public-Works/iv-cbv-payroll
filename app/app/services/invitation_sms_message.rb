# Renders the SMS bodies for an invitation. The single source of truth for
# message content: InvitationSmsJob sends exactly what this returns, and the
# admin portal's status page previews it, so the two cannot drift.
class InvitationSmsMessage
  class << self
    def invitation_body(invitation)
      agency = agency_for(invitation)
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

    # Not agency-branded: Digital Public Works is the sending party of record
    # for 10DLC purposes, so this copy is fixed rather than per-partner.
    def consent_notice_body(invitation)
      I18n.with_locale(invitation.language) do
        ApplicationController.helpers.agency_translation_for(
          agency_for(invitation),
          "applicant_sms.consent_notice.body"
        )
      end
    end

    private

    def agency_for(invitation)
      ClientAgencyConfig.instance[invitation.client_agency_id]
    end
  end
end
