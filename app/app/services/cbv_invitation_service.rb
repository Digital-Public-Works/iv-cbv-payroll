class CbvInvitationService
  def initialize(event_logger)
    @event_logger = event_logger
  end

  def invite(cbv_flow_invitation_params, current_user, delivery_method: :email, expiration_params: {})
    cbv_flow_invitation_params[:user] = current_user
    @cbv_flow_invitation = CbvFlowInvitation.new(cbv_flow_invitation_params)
    @agency_config = Rails.application.config.client_agencies[current_user.client_agency_id]
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
      @cbv_flow_invitation.errors.add(:expiration, "Provide either expiration_days or expiration_date, but not both.")
      return
    end

    if expiration_params[:expiration_date].present?
      begin
        parsed_date = Time.iso8601(expiration_params[:expiration_date].to_s)

        if parsed_date < Time.current
          @cbv_flow_invitation.errors.add(:expiration_date, "cannot be in the past")
          return
        elsif parsed_date > 1.year.from_now
          @cbv_flow_invitation.errors.add(:expiration_date, "cannot be more than 1 year in the future")
          return
        end

      rescue ArgumentError
        @cbv_flow_invitation.errors.add(:expiration_date, "must be a full ISO8601 datetime with a timezone")
        return
      end
    end

    if expiration_params[:expiration_days].present?
      exp_days = expiration_params[:expiration_days].to_i
      if exp_days < 1 || (Time.current + exp_days.days) > 1.year.from_now
        @cbv_flow_invitation.errors.add(:expiration_days, "cannot be more than 1 year in the future")
        nil
      end
    end
  end

  def calculate_expires_at(exp_params)
    Time.use_zone(@agency_config.timezone) do
      if exp_params[:expiration_date].present?
        Time.zone.parse(exp_params[:expiration_date])
      elsif exp_params[:expiration_days].present?
        Time.current.end_of_day + exp_params[:expiration_days].to_i.days
      else
        Time.current.end_of_day + @agency_config.invitation_valid_days.days
      end
    end
  end
end
