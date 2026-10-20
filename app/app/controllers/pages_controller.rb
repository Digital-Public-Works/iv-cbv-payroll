class PagesController < ApplicationController
  before_action :redirect_to_client_agency_entries, only: %i[home]

  def home
    flash.now[:slim_alert] = { "type" => "info", "message_html" => t("cbv.error_missing_token_html") } if params[:cbv_flow_timeout].present?
  end

  def error_404
    # When in development environment, you'll need to set
    #   config.consider_all_requests_local = false
    # in config/development.rb for these pages to actually show up.
    @cbv_flow = if session[:cbv_flow_id]
                  CbvFlow.find(session[:cbv_flow_id])
                end

    render status: :not_found, formats: %i[html]
  end

  def error_500
    # When in development environment, you'll need to set
    #   config.consider_all_requests_local = false
    # in config/development.rb for these pages to actually show up.

    render status: :internal_server_error, formats: %i[html]
  end

  private

  # A partner's bare domain is the address applicants are given, so send it into
  # the generic flow at /start. The partner is identified there by the same
  # subdomain, so nothing needs to be passed along but the origin.
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
