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

  def redirect_to_client_agency_entries
    # Don't redirect to CBV flow if the pilot has ended - let the home page render the pilot end message
    return if pilot_ended?

    # Don't redirect if we just came from a CBV flow timeout
    return if params[:cbv_flow_timeout].present?

    client_agency_id = detect_client_agency_from_domain
    if client_agency_id.present?
      agency = agency_config[client_agency_id]

      # Don't redirect agencies that have disabled generic links
      return if agency&.generic_links_disabled

      session[:cbv_origin] = params[:origin] || agency&.default_origin
      redirect_to cbv_flow_new_path(client_agency_id: client_agency_id)
    end
  end
end
