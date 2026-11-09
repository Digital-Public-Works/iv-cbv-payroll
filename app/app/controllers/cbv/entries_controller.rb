class Cbv::EntriesController < Cbv::BaseController
  before_action :redirect_to_landing_page_if_needed

  def show
    event_logger.track(TrackEvent::ApplicantViewedAgreement, request, {
      time: Time.now.to_i,
      client_agency_id: current_agency&.id,
      cbv_applicant_id: @cbv_flow.cbv_applicant_id,
      cbv_flow_id: @cbv_flow.id,
      device_id: @cbv_flow.device_id,
      invitation_id: @cbv_flow.cbv_flow_invitation_id,
      origin: session[:cbv_origin]
    })
  end

  def create
    if params["agreement"] == "1"
      event_logger.track(TrackEvent::ApplicantAgreed, request, {
        time: Time.now.to_i,
        client_agency_id: current_agency&.id,
        cbv_applicant_id: @cbv_flow.cbv_applicant_id,
        cbv_flow_id: @cbv_flow.id,
        device_id: @cbv_flow.device_id,
        invitation_id: @cbv_flow.cbv_flow_invitation_id,
        origin: session[:cbv_origin]
      })
      redirect_to next_path
    else
      redirect_to(cbv_flow_entry_path, flash: { alert: t(".error") })
    end
  end

  private

  # check if a landing page redirect is needed because the partner is configured to collect
  # a user-provided value on the landing page (IE case number)
  def redirect_to_landing_page_if_needed
    return unless @cbv_flow.generic?
    return if @cbv_flow.landing_page_completed?

    redirect_to cbv_flow_landing_page_path
  end
end
