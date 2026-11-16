# admin management of api tokens for partners
module AdminApi
  class ApiTokens
    MAX_ACTIVE = 2
    MAX_EXPIRY_DAYS = 30
    DEFAULT_GRACE_HOURS = 48

    def initialize(partner_id)
      @partner_id = partner_id
    end

    def list
      signing_id = signing_token_id
      active, inactive = partner_tokens.includes(:user).to_a.partition(&:active?)
      active.sort_by!(&:created_at)
      inactive = inactive.sort_by { |t| [ ended_at(t), t.id ] }.reverse
      (active + inactive).map { |token| summary(token, signing_id) }
    end

    def create(user: nil)
      token = locked do
        if active_tokens.exists?
          raise AdminApi::Errors::Conflict, "'#{@partner_id}' already has an active API token; rotate it instead"
        end

        (user || service_account).api_access_tokens.create!
      end
      created(token)
    end

    def find_or_create_value
      existing = active_tokens.order(:created_at).first
      existing ? existing.access_token : create[:access_token]
    end

    # generates new token and sets the old one's expiry
    def rotate(token_id, expires_at: nil)
      token = locked do
        old = find(token_id)
        raise AdminApi::Errors::Conflict, "API token #{old.id} is already expiring; it can't be rotated" if old.expires_at

        count = active_tokens.count
        if count >= MAX_ACTIVE
          raise AdminApi::Errors::Conflict, "'#{@partner_id}' already has #{count} active API tokens; expire the extra ones before rotating"
        end

        new_token = old.user.api_access_tokens.create!
        old.update!(expires_at: valid_expiry(expires_at.presence || DEFAULT_GRACE_HOURS.hours.from_now))
        new_token
      end
      created(token)
    end

    def set_expiry(token_id, expires_at)
      locked { find(token_id).update!(expires_at: valid_expiry(expires_at)) }
    end

    def expire_now(token_id)
      locked { find(token_id).update!(expires_at: Time.current) }
    end

    def reveal(token_id)
      find(token_id).access_token
    end

    private

    def summary(token, signing_id)
      {
        id: token.id,
        user_email: token.user.email,
        created_at: token.created_at.iso8601(3),
        expires_at: token.expires_at&.iso8601(3),
        revoked_at: token.deleted_at&.iso8601(3),
        status: status(token),
        last_four: token.access_token.to_s.last(4),
        json_signing_key: token.id == signing_id
      }
    end

    def partner_tokens
      ApiAccessToken.joins(:user).where(users: { client_agency_id: @partner_id, is_service_account: true })
    end

    def active_tokens
      partner_tokens.active
    end

    def find(token_id)
      active_tokens.find_by(id: token_id) || raise(AdminApi::Errors::NotFound, "No active API token #{token_id} for '#{@partner_id}'")
    end

    def locked
      ApplicationRecord.transaction do
        PartnerConfig.lock.find_by(partner_id: @partner_id)
        yield
      end
    end

    def valid_expiry(value)
      time = parse_time(value)
      raise AdminApi::Errors::BadRequest, "expires_at must be in the future" unless time.future?
      if time > MAX_EXPIRY_DAYS.days.from_now
        raise AdminApi::Errors::BadRequest, "expires_at can be at most #{MAX_EXPIRY_DAYS} days away"
      end

      time
    end

    def parse_time(value)
      return value.in_time_zone if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)

      Time.iso8601(value.to_s).in_time_zone
    rescue ArgumentError
      raise AdminApi::Errors::BadRequest, "expires_at must be an ISO 8601 time, e.g. 2026-11-17T15:00:00Z"
    end

    def status(token)
      return "revoked" if token.deleted_at
      return "expired" unless token.active?

      token.expires_at ? "expiring" : "active"
    end

    def ended_at(token)
      [ token.deleted_at, token.expires_at ].compact.min || token.created_at
    end

    def signing_token_id
      User.signing_token_for_agency(@partner_id)&.id
    end

    def created(token)
      { **summary(token, signing_token_id), access_token: token.access_token }
    end

    def service_account
      existing = User.where(client_agency_id: @partner_id, is_service_account: true).order(:created_at).first
      return existing if existing

      user = User.find_or_create_by!(email: "ffs-eng+#{@partner_id}@digitalpublicworks.org", client_agency_id: @partner_id)
      user.update!(is_service_account: true)
      user
    end
  end
end
