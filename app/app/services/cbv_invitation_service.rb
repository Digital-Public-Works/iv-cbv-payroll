class CbvInvitationService
  def initialize(event_logger)
    @event_logger = event_logger
  end

  def invite(cbv_flow_invitation_params, current_user, communication_channel: :email, metrics_attributes: {})
    cbv_flow_invitation_params[:user] = current_user
    cbv_flow_invitation = CbvFlowInvitation.new(cbv_flow_invitation_params)
    cbv_flow_invitation.communication_channel = communication_channel.to_s if communication_channel.present?

    return cbv_flow_invitation unless cbv_flow_invitation.save

    deliver(cbv_flow_invitation, communication_channel)

    track_event(cbv_flow_invitation, current_user, metrics_attributes)

    cbv_flow_invitation
  end

  private

  def track_event(cbv_flow_invitation, current_user, metrics_attributes = {})
    system_properties = {
      time: Time.now.to_i,
      user_id: current_user.id,
      caseworker_email_address: current_user.email,
      client_agency_id: current_user.client_agency_id,
      cbv_applicant_id: cbv_flow_invitation.cbv_applicant_id,
      invitation_id: cbv_flow_invitation.id,
      communication_channel: cbv_flow_invitation.communication_channel
    }

    # guard against possible future key collision, system_property will override
    @event_logger.track(
      TrackEvent::CaseworkerInvitedApplicantToFlow,
      nil,
      (metrics_attributes || {}).merge(system_properties)
    )
  end

  def deliver(cbv_flow_invitation, communication_channel)
    case communication_channel
    when :email
      send_invitation_email(cbv_flow_invitation)
    when :link, nil
      Rails.logger.info "Generated invitation ID: #{cbv_flow_invitation.id} (no communication channel specified)"
    else
      raise ArgumentError.new("Unknown communication_channel: #{communication_channel}")
    end
  end

  def send_invitation_email(cbv_flow_invitation)
    ApplicantMailer.with(
      cbv_flow_invitation: cbv_flow_invitation
    ).invitation_email.deliver_now
  end
end
