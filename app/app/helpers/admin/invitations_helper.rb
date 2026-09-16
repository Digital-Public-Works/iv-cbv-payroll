module Admin
  module InvitationsHelper
    # Preview of what the applicant will receive, shown on the invitation
    # status board. Both channels render through the same code path as the
    # real send (InvitationSmsMessage / ApplicantMailer), so the preview is
    # verbatim and cannot drift from what goes out.
    def communication_preview(invitation, communication)
      if communication.channel_sms?
        InvitationSmsMessage.invitation_body(invitation)
      elsif communication.channel_email?
        email_preview(invitation)
      end
    end

    private

    def email_preview(invitation)
      mail = ApplicantMailer.with(cbv_flow_invitation: invitation).invitation_email

      subject_line = t("admin.invitations.show.email_subject_line", subject: mail.subject)
      body_text = mail.body.to_s
        .then { |html| strip_tags(html) }
        .lines
        .map(&:strip)
        .reject(&:blank?)
        .join("\n\n")

      "#{subject_line}\n\n#{body_text}"
    end
  end
end
