class Caseworker::BaseController < ApplicationController
  before_action :ensure_known_agency
  before_action :redirect_if_disabled

  def authenticate_user!
    super

    unless current_user.client_agency_id == params[:client_agency_id]
      redirect_to root_url, flash: {
        slim_alert: { message: t("shared.error_unauthorized"), type: "error" }
      }
    end
  end

  def redirect_if_disabled
    unless current_agency.staff_portal_enabled
      redirect_to root_url, flash: {
        slim_alert: { message: I18n.t("caseworker.entries.disabled"), type: "error" }
      }
    end
  end

  private

  # Partner routes are validated dynamically by ClientAgencyIdConstraint, so a
  # request only reaches here for a known partner. This is defense-in-depth for
  # any path that bypasses routing (e.g. direct controller invocation): an
  # unknown partner has no route, so treat it as a 404 rather than blowing up on
  # a nil agency.
  def ensure_known_agency
    raise ActionController::RoutingError, "No partner configured for #{params[:client_agency_id].inspect}" if current_agency.nil?
  end
end
