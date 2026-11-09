# auto-create an invitation when a user comes from a generic link.
class AutoInvitationService
  def initialize(event_logger = nil)
    @event_logger = event_logger
  end

  def create_for(client_agency_id:, device_id: nil, language: I18n.locale, request: nil)
    unless self.class.available_for?(client_agency_id)
      Rails.logger.warn("Refusing to create a generic-link invitation for #{client_agency_id}: generic links are not enabled")
      return nil
    end

    invitation = build(client_agency_id, language)

    unless invitation.save
      Rails.logger.error(
        "Unable to auto-create invitation for #{client_agency_id}: #{invitation.errors.full_messages.join(', ')}"
      )
      return nil
    end

    track_created_event(invitation, device_id, request)

    invitation
  end

  # Whether this partner offers the generic flow at all. Every entry point into
  # it is gated on this: the /start action, the invitation this service hands
  # back, the flow started from an auto-created invitation's link, and the
  # shareable link offered on the success page.
  def self.available_for?(client_agency_id)
    !!ClientAgencyConfig.instance[client_agency_id]&.generic_flow_available?
  end

  private

  def build(client_agency_id, language)
    user = User.system_account_for(client_agency_id)

    CbvFlowInvitation.new(
      user: user,
      client_agency_id: client_agency_id,
      # No applicant email is known at this point. Mirrors the partner API, which
      # also stamps the invitation with the creating account's email.
      email_address: user.email,
      language: language.to_s,
      auto_created: true,
      cbv_applicant: CbvApplicant.new(client_agency_id: client_agency_id)
    )
  end

  def track_created_event(invitation, device_id, request)
    return if @event_logger.nil?

    @event_logger.track(TrackEvent::ApplicantAutoCreatedInvitation, request, {
      time: Time.now.to_i,
      invitation_id: invitation.id,
      cbv_applicant_id: invitation.cbv_applicant_id,
      client_agency_id: invitation.client_agency_id,
      device_id: device_id
    })
  end
end
