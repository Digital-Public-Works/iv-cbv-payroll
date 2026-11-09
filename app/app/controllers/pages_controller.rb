class PagesController < ApplicationController
  skip_before_action :set_device_id_cookie, only: %i[error_404 error_500]

  before_action :redirect_to_client_agency_entries, only: %i[home]

  def home
    flash.now[:slim_alert] = { "type" => "info", "message_html" => t("cbv.error_missing_token_html") } if params[:cbv_flow_timeout].present?
  end

  # in dev set config.consider_all_requests_local = false to see these pages
  def error_404
    @cbv_flow = CbvFlow.find_by(id: session[:cbv_flow_id]) if session[:cbv_flow_id]

    render status: :not_found, formats: %i[html]
  end

  def error_500
    render status: :internal_server_error, formats: %i[html]
  end

  private

  def redirect_to_client_agency_entries
    # Don't redirect if we just came from a CBV flow timeout
    return if params[:cbv_flow_timeout].present?

    client_agency_id = detect_client_agency_from_domain
    return if client_agency_id.blank?

    # Only agencies that offer the generic flow get sent into it
    return unless agency_config[client_agency_id]&.generic_links_enabled

    redirect_to start_path(origin: params[:origin].presence)
  end
end
