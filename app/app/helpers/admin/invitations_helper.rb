module Admin
  module InvitationsHelper
    # Preview of what the applicant will receive, shown on the invitation
    # status board. SMS shows the exact message body (via the same renderer
    # the send job uses); email shows a plain-language summary of what
    # they'll get rather than rendered HTML.
    def communication_preview(invitation, communication)
      if communication.channel_sms?
        InvitationSmsMessage.invitation_body(invitation)
      elsif communication.channel_email?
        subject = I18n.with_locale(invitation.language) do
          agency_translation_for(selected_agency, "applicant_mailer.invitation_email.subject")
        end
        t("admin.invitations.show.email_preview", subject: subject)
      end
    end
  end
end
