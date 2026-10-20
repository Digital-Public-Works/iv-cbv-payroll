# Entry point for a partner's generic link: `<partner>.verifymyincome.org/start`.

class Cbv::GenericLinksController < Cbv::BaseController
  skip_before_action :set_cbv_flow
  skip_after_action :capture_page_view
  prepend_before_action :set_cbv_origin
  before_action :set_generic_link_agency
  before_action :redirect_unless_generic_links_enabled

  def show
    invitation = AutoInvitationService.new(event_logger).create_for(
      client_agency_id: @client_agency_id,
      device_id: cookies.permanent.signed[:device_id],
      language: I18n.locale,
      request: request
    )

    if invitation.blank?
      return redirect_to root_url, flash: { alert: t("cbv.error_invalid_link") }
    end

    session[:cbv_generic_entry] = true

    track_generic_link_clicked_event(invitation)

    redirect_to start_flow_path({
      token: invitation.auth_token,
      locale: I18n.locale,
      origin: params[:origin].presence
    }.compact)
  end

  private

  def set_generic_link_agency
    @client_agency_id = detect_client_agency_from_domain
    @generic_link_agency = agency_config[@client_agency_id] if @client_agency_id.present?

    redirect_to root_url if @generic_link_agency.blank?
  end

  # insta redirect if generic links are not enabled for this partner
  def redirect_unless_generic_links_enabled
    redirect_to root_url unless @generic_link_agency&.generic_links_enabled
  end

  def track_generic_link_clicked_event(invitation)
    # Skip tracking this event for a specific user agent, since link scanners
    # behind SMS delivery generate a lot of traffic from it
    return if request.user_agent&.match?(/go-http-client/i)

    event_logger.track(TrackEvent::ApplicantClickedGenericLink, request, {
      time: Time.now.to_i,
      cbv_applicant_id: invitation.cbv_applicant_id,
      invitation_id: invitation.id,
      client_agency_id: @client_agency_id,
      device_id: cookies.permanent.signed[:device_id],
      origin: params[:origin],
      # keeping this as future proofing in case we decide to implement generic session re-use
      is_new_session: true
    })
  end
end
