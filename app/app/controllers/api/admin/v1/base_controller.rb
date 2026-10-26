# Base for the partner-config admin API, called only by the vmi-admin portal.
#
# The routes exist only while AdminApi::Config.enabled? (see routes.rb).
# all actions require a request signed with the service secret, naming the
# operator in the signed actor header.
class Api::Admin::V1::BaseController < ActionController::API
  ADMIN_PATH_PREFIX = "/api/admin/"

  before_action :require_canonical_admin_path
  before_action :authenticate_admin_request

  rescue_from AdminApi::Errors::Base do |e|
    render json: e.body, status: e.status
  end

  rescue_from ActiveRecord::RecordNotFound do
    render json: { message: "Unknown partner '#{params[:partner_id]}'" }, status: :not_found
  end

  # don't accidentally log / return messages that may contain secrets
  rescue_from ActionDispatch::Http::Parameters::ParseError do
    error = AdminApi::Errors::BadRequest.new("The request body is not valid JSON")
    render json: error.body, status: error.status
  end

  attr_reader :current_actor

  private

  # The request body as parsed JSON. Read from the raw body, not params, so
  # the documents arrive exactly as sent.
  def body_json
    @body_json ||= begin
      parsed = request.raw_post.present? ? JSON.parse(request.raw_post) : {}
      raise AdminApi::Errors::BadRequest, "The request body must be a JSON object" unless parsed.is_a?(Hash)
      parsed
    end
  rescue JSON::ParserError
    raise AdminApi::Errors::BadRequest, "The request body is not valid JSON"
  end

  def find_partner
    @partner = PartnerConfig.find_by!(partner_id: params[:partner_id])
  end

  def render_detail(partner_config)
    render json: AdminApi::PartnerDocuments.detail(partner_config.reload)
  end

  def logged(action, partner_id:, changed: [], **extra)
    result = "ok"
    yield
  rescue AdminApi::Errors::Base => e
    result = Rack::Utils.status_code(e.status)
    raise
  rescue ActiveRecord::RecordNotFound
    result = 404
    raise
  rescue StandardError
    result = 500
    raise
  ensure
    AdminApi::ActionLog.record(action: action, actor: current_actor, partner_id: partner_id, changed: changed, result: result, **extra)
  end

  # ALB refuses /api/admin, also refuse paths like /api//admin
  def require_canonical_admin_path
    original_path = request.original_fullpath.split("?", 2).first
    head :not_found unless original_path.start_with?(ADMIN_PATH_PREFIX)
  end

  def authenticate_admin_request
    secret = AdminApi::Config.service_secret
    return head(:not_found) if secret.nil?

    if AdminApi::RequestSignature.valid_request?(request, secret)
      @current_actor = request.headers[AdminApi::RequestSignature::ACTOR_HEADER]
    else
      Rails.logger.warn("Admin API: rejected unauthenticated request to #{request.path}")
      NewRelic::Agent.record_custom_event("AdminApiAuthFailure", path: request.path, method: request.request_method) if defined?(NewRelic::Agent)
      render json: { errors: [ { message: "Unauthorized" } ] }, status: :unauthorized
    end
  end
end
