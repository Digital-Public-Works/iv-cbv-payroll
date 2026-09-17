# Platform-admin portal (ADR-0002), branded "VMI Caseworker Portal": operated
# by DPW staff across all partners. No authentication yet — the route
# constraint plus ensure_portal_enabled keep it out of deployed environments
# until the OmniAuth follow-up.
class Admin::BaseController < ApplicationController
  before_action :ensure_portal_enabled
  before_action :require_agency!
  before_action :extend_session_expiry

  helper_method :selected_agency, :selected_agency_id

  private

  # The app-wide session cookie expires after 30 minutes (an applicant-flow
  # security choice). Admin pages override it per request so a caseworker's
  # session — and its CSRF token — survives a workday of intermittent use.
  def extend_session_expiry
    request.session_options[:expire_after] = Rails.application.config.admin_session_expires_after
  end

  def ensure_portal_enabled
    raise ActionController::RoutingError.new("Admin portal is disabled") unless Rails.application.config.admin_portal_enabled
  end

  # The working agency is inferred from the partner subdomain
  # (e.g. wc.<domain>/admin). The bare domain has no agency; require_agency!
  # sends those requests to the agency sitemap.
  def selected_agency_id
    @selected_agency_id ||= detect_client_agency_from_domain
  end

  def selected_agency
    selected_agency_id && agency_config[selected_agency_id]
  end

  # In the admin portal the "current" agency is always the inferred one, so
  # agency-aware helpers (agency_translation, acronyms) work unchanged.
  def current_agency
    selected_agency
  end

  def require_agency!
    redirect_to admin_agencies_path if selected_agency_id.blank?
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
