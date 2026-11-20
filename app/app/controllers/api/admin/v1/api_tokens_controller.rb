class Api::Admin::V1::ApiTokensController < Api::Admin::V1::BaseController
  before_action :find_partner

  def index
    render json: { api_tokens: tokens.list }
  end

  def create
    logged("create_api_token", partner_id: @partner.partner_id) do
      render json: { api_token: tokens.create }, status: :created
    end
  end

  def reveal
    logged("reveal_api_token", **token_log) do
      render json: { access_token: tokens.reveal(params[:token_id]) }
    end
  end

  # default expiration on rotate is 48 hrs from 'now'
  def rotate
    logged("rotate_api_token", **token_log, expires_at: body_json["expires_at"]) do
      render json: { api_token: tokens.rotate(params[:token_id], expires_at: body_json["expires_at"]) }, status: :created
    end
  end

  # Body: { "expires_at": ISO 8601 } (required).
  def update_expiry
    logged("set_api_token_expiry", **token_log, expires_at: body_json["expires_at"]) do
      tokens.set_expiry(params[:token_id], body_json["expires_at"])
      render json: { api_tokens: tokens.list }
    end
  end

  def expire
    logged("expire_api_token", **token_log) do
      tokens.expire_now(params[:token_id])
      render json: { api_tokens: tokens.list }
    end
  end

  private

  def tokens
    @tokens ||= AdminApi::ApiTokens.new(@partner.partner_id)
  end

  def token_log
    { partner_id: @partner.partner_id, token_id: params[:token_id] }
  end
end
