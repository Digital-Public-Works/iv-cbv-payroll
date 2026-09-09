class Admin::InvitationsController < Admin::BaseController
  # Channels offered by this form. Email is deliberately absent until email
  # delivery ships.
  FORM_CHANNELS = %w[link sms].freeze

  helper_method :language_options

  def index
    @invitations = admin_invitations
      .includes(:invitation_communications, :cbv_applicant)
      .where(client_agency_id: selected_agency_id)
      .where(created_at: 24.hours.ago..)
      .order(created_at: :desc)
  end

  def new
    @cbv_flow_invitation = CbvFlowInvitation.new(
      client_agency_id: selected_agency_id,
      language: "en",
      communication_channel: "link"
    )
  end

  def create
    channel = FORM_CHANNELS.include?(invitation_params[:communication_channel]) ? invitation_params[:communication_channel] : "link"

    if channel == "sms" && params[:sms_attestation] != "1"
      @cbv_flow_invitation = build_unsaved_invitation(channel)
      flash.now[:alert] = t(".attestation_required")
      return render :new, status: :unprocessable_content
    end

    # client_agency_id must be assigned before any partner-defined applicant
    # attribute: CbvApplicant resolves those dynamically per agency, and
    # assignment happens in hash order.
    applicant_attributes = { client_agency_id: selected_agency_id }
      .merge(invitation_params[:cbv_applicant_attributes]&.to_h || {})

    @cbv_flow_invitation = CbvInvitationService.new(event_logger).invite(
      invitation_params.except(:communication_channel).merge(
        client_agency_id: selected_agency_id,
        cbv_applicant_attributes: applicant_attributes
      ),
      system_user,
      communication_channel: channel.to_sym
    )

    if @cbv_flow_invitation.errors.any?
      flash.now[:alert] = @cbv_flow_invitation.errors.full_messages.join(" ")
      return render :new, status: :unprocessable_content
    end

    # Keyword form: positional args would fill the optional :locale segment.
    redirect_to admin_invitation_path(id: @cbv_flow_invitation.id)
  end

  def show
    @invitation = admin_invitations.find(params[:id])
    @communication = latest_communication(@invitation)
  end

  # Polled by the status board (Stimulus polling_controller) while an SMS
  # send is in flight; replies with a Turbo Stream replacing the status panel.
  def status
    @invitation = admin_invitations.find(params[:id])
    @communication = latest_communication(@invitation)

    render turbo_stream: turbo_stream.replace(
      :invitation_status,
      partial: "admin/invitations/status",
      locals: { invitation: @invitation, communication: @communication }
    )
  end

  # Manual retry of a failed send. Each attempt is its own communication row
  # (see InvitationCommunication), so the failed attempt stays in the history
  # and the status board follows the new one.
  def resend
    @invitation = admin_invitations.find(params[:id])
    communication = latest_communication(@invitation)

    if communication&.status_failed?
      retry_communication = @invitation.invitation_communications.create!(channel: communication.channel)
      InvitationSmsJob.perform_later(retry_communication.id)
    else
      flash[:alert] = t(".not_failed")
    end

    redirect_to admin_invitation_path(id: @invitation.id)
  end

  private

  def latest_communication(invitation)
    invitation.invitation_communications.order(:created_at).last
  end

  def language_options
    CbvFlowInvitation::VALID_LOCALES.each_with_object({}) do |lang, options|
      options[lang] = I18n.t(".shared.languages.#{lang}", default: lang.to_s.titleize)
    end
  end

  def build_unsaved_invitation(channel)
    CbvFlowInvitation.new(
      invitation_params.except(:cbv_applicant_attributes).merge(
        client_agency_id: selected_agency_id,
        communication_channel: channel
      )
    )
  end

  def invitation_params
    valid_applicant_attributes = CbvApplicant.valid_attributes_for_agency(selected_agency_id)

    params.fetch(:cbv_flow_invitation, {}).permit(
      :language,
      :phone_number,
      :communication_channel,
      cbv_applicant_attributes: valid_applicant_attributes
    )
  end
end
