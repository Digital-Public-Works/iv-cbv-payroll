class Cbv::SessionsController < Cbv::BaseController
  skip_before_action :set_cbv_flow, :ensure_cbv_flow_not_yet_complete, :prevent_back_after_complete
  skip_after_action :capture_page_view

  # switching to server side timeout to handle multiple tabs, timeout 'close' to timeout window since browser and session timers start is not synced
  END_TOLERANCE = 1.minute

  SWITCHED_REASON_OPEN_ELSEWHERE = "open_elsewhere".freeze

  def refresh
    cbv_flow = CbvFlow.find_by(id: session[:cbv_flow_id])
    return redirect_for_tab_flow_mismatch if cbv_flow && tab_flow_mismatch?(cbv_flow)

    session[:last_seen] = Time.current.to_i
    head :ok
  end

  # verify that one tab timing out doesn't end all tab activity if another had recent activity
  def end
    timed_out = params[:timeout].present?

    if timed_out && active_in_another_tab?
      Rails.logger.info "Not ending session in sessions#end: another tab was active #{seconds_since_last_seen}s ago"
      return redirect_to cbv_flow_session_switched_path(reason: SWITCHED_REASON_OPEN_ELSEWHERE, locale: I18n.locale)
    end

    cbv_flow = CbvFlow.find_by(id: session[:cbv_flow_id])
    track_session_timed_out(cbv_flow) if timed_out

    redirect_target = if cbv_flow
                        cbv_flow_session_timeout_path(client_agency_id: cbv_flow.client_agency_id, locale: I18n.locale)
                      else
                        Rails.logger.info "Unable to find CbvFlow in sessions#end. Redirecting to root with timeout"
                        root_url(cbv_flow_timeout: true, locale: I18n.locale)
                      end

    reset_cbv_session!
    redirect_to redirect_target
  end

  def timeout
    reset_cbv_session!
    @current_agency = agency_config[params[:client_agency_id]]

    unless @current_agency
      redirect_to root_url(cbv_flow_timeout: true)
    end
  end

  def switched
    @open_elsewhere = params[:reason] == SWITCHED_REASON_OPEN_ELSEWHERE
    @hide_session_timeout = true
    session_flow = CbvFlow.find_by(id: session[:cbv_flow_id]) if session[:cbv_flow_id].present?
    @current_agency = agency_config[session_flow&.client_agency_id] ||
      agency_config[detect_client_agency_from_domain]
  end

  def current_agency
    @current_agency
  end

  private

  def active_in_another_tab?
    return false if session[:cbv_flow_id].blank?

    seconds = seconds_since_last_seen
    seconds.present? && seconds < (Rails.application.config.cbv_session_expires_after - END_TOLERANCE).to_i
  end

  def track_session_timed_out(cbv_flow)
    event_logger.track(TrackEvent::ApplicantTimedOut, request, {
      time: Time.now.to_i,
      cbv_flow_id: cbv_flow&.id,
      cbv_applicant_id: cbv_flow&.cbv_applicant_id,
      client_agency_id: cbv_flow&.client_agency_id,
      device_id: cbv_flow&.device_id,
      invitation_id: cbv_flow&.cbv_flow_invitation_id
    }.compact)
  end

  def seconds_since_last_seen
    last_seen = session[:last_seen]
    return nil if last_seen.blank?

    Time.current.to_i - last_seen.to_i
  end
end
