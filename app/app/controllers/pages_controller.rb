class PagesController < ApplicationController
  # These two actions back config.exceptions_app, so they render for every
  # unmatched request the app receives -- which in practice is mostly
  # vulnerability scanners walking a wordlist (/.env, /wp-admin,
  # /admin/wp-config.bak, ...). Minting a device_id there hands a tracking
  # identifier to crawlers that will never come back, and costs a UUID, an HMAC
  # and a Set-Cookie header on a response that is never part of a session. A real
  # person who happens to land on an error page first gets their device_id on the
  # next page they load.
  skip_before_action :set_device_id_cookie, only: %i[error_404 error_500]

  before_action :redirect_to_client_agency_entries, only: %i[home]

  def home
    flash.now[:slim_alert] = { "type" => "info", "message_html" => t("cbv.error_missing_token_html") } if params[:cbv_flow_timeout].present?
  end

  def error_404
    # When in development environment, you'll need to set
    #   config.consider_all_requests_local = false
    # in config/development.rb for these pages to actually show up.

    # find_by, not find: session[:cbv_flow_id] can point at a flow that has since
    # been deleted (data retention), and a RecordNotFound raised here escapes the
    # error handler itself -- replacing this page with Rails' static fallback.
    @cbv_flow = CbvFlow.find_by(id: session[:cbv_flow_id]) if session[:cbv_flow_id]

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
