# Platform-admin portal (ADR-0002): operated by DPW staff across all
# partners. No authentication yet — the route constraint plus
# ensure_portal_enabled keep it out of deployed environments until the
# OmniAuth follow-up.
class Admin::BaseController < ApplicationController
  before_action :ensure_portal_enabled

  helper_method :selected_agency, :selected_agency_id, :agency_options

  private

  def ensure_portal_enabled
    raise ActionController::RoutingError.new("Admin portal is disabled") unless Rails.application.config.admin_portal_enabled
  end

  # The portal is cross-agency; the working agency comes from (in order) the
  # explicit selector param, the session, the partner subdomain, or the first
  # configured agency.
  def selected_agency_id
    @selected_agency_id ||= begin
      candidate = params[:client_agency_id].presence ||
        session[:admin_client_agency_id].presence ||
        detect_client_agency_from_domain

      id = agency_config.client_agency_ids.include?(candidate) ? candidate : agency_config.client_agency_ids.first
      session[:admin_client_agency_id] = id
      id
    end
  end

  def selected_agency
    agency_config[selected_agency_id]
  end

  # In the admin portal the "current" agency is always the selected one, so
  # agency-aware helpers (agency_translation, acronyms) work unchanged.
  def current_agency
    selected_agency
  end

  def agency_options
    agency_config.client_agency_ids
  end

  # Invitations created through /admin are owned by the per-agency system
  # user until real admin identities exist (ADR-0002).
  def system_user
    User.admin_system_user_for(selected_agency_id)
  end

  def admin_invitations
    CbvFlowInvitation.joins(:user).where(users: { email: User::ADMIN_SYSTEM_USER_EMAIL })
  end
end
