class CbvInvitationService
  def initialize(event_logger)
    @event_logger = event_logger
  end

  def invite(cbv_flow_invitation_params, current_user, delivery_method: :email, expiration_params: {})
    cbv_flow_invitation_params[:user] = current_user
    @cbv_flow_invitation = CbvFlowInvitation.new(cbv_flow_invitation_params)
    @agency_config = agency_config(current_user)
    validate_expiration_params(expiration_params)

    if @cbv_flow_invitation.errors.empty?
      expires_at = calculate_expires_at(expiration_params)
      @cbv_flow_invitation.expires_at = expires_at
      @cbv_flow_invitation.save
    end

    if @cbv_flow_invitation.errors.any?
      e = @cbv_flow_invitation.errors.full_messages.join(", ")
      Rails.logger.warn("Error inviting applicant: #{e}")
      return @cbv_flow_invitation
    end

    case delivery_method
    when :email
      send_invitation_email(@cbv_flow_invitation)
    when nil
      Rails.logger.info "Generated invitation ID: #{@cbv_flow_invitation.id} (no delivery method specified)"
    else
      raise ArgumentError.new("Unknown delivery_method: #{delivery_method}")
    end

    track_event(@cbv_flow_invitation, current_user)

    @cbv_flow_invitation
  end

  private

  def track_event(cbv_flow_invitation, current_user)
    @event_logger.track(TrackEvent::CaseworkerInvitedApplicantToFlow, nil, {
      time: Time.now.to_i,
      user_id: current_user.id,
      caseworker_email_address: current_user.email,
      client_agency_id: current_user.client_agency_id,
      cbv_applicant_id: cbv_flow_invitation.cbv_applicant_id,
      invitation_id: cbv_flow_invitation.id
    })
  end

  def send_invitation_email(cbv_flow_invitation)
    ApplicantMailer.with(
      cbv_flow_invitation: cbv_flow_invitation
    ).invitation_email.deliver_now
  end

  def validate_expiration_params(expiration_params)
    if expiration_params[:expiration_days].present? && expiration_params[:expiration_date].present?
      @cbv_flow_invitation.errors.add(:expiration, "Provide either expiration_days or expiration_date, but not both")
    end

    if expiration_params[:expiration_date].present?
      parsed_date = Time.use_zone(agency_time_zone) { Time.zone.parse(expiration_params[:expiration_date].to_s) }

      if parsed_date.nil?
        @cbv_flow_invitation.errors.add(:expiration_date, "is not a valid date format")
      elsif parsed_date < Time.use_zone(agency_time_zone) { Time.current }
        @cbv_flow_invitation.errors.add(:expiration_date, "cannot be in the past")
      elsif parsed_date > Time.use_zone(agency_time_zone) { Time.zone.today } + 366.days
        @cbv_flow_invitation.errors.add(:expiration_date, "cannot be more than 1 year in the future")
      end
    end

    if expiration_params[:expiration_days].present?
      if expiration_params[:expiration_days].to_i < 1 || expiration_params[:expiration_days].to_i > 366
        @cbv_flow_invitation.errors.add(:expiration_days, "must be between 1 and 366")
      end
    end
  end

  def calculate_expires_at(exp_params)
    end_of_day_created = Time.use_zone(agency_time_zone) { Time.current }.end_of_day
    days_valid_for  = exp_params[:expiration_days] || @agency_config.invitation_valid_days

    exp_params[:expiration_date]&.end_of_day || end_of_day_created + days_valid_for.days
  end

  def agency_config(current_user)
    Rails.application.config.client_agencies[current_user.client_agency_id] || {}
  end

  def agency_time_zone
    @agency_config.timezone || Rails.configuration.time_zone
  end
end
