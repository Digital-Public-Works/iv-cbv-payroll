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
        active = active_tokens.to_a
        if active.any? { |t| t.expires_at.nil? }
          raise AdminApi::Errors::Conflict, "'#{@partner_id}' already has an active API token; rotate it instead"
        end
        if active.size > 1
          raise AdminApi::Errors::Conflict, "'#{@partner_id}' already has #{active.size} active API tokens; expire the extra ones first"
        end

        (user || service_account).api_access_tokens.create!
      end
      created(token)
    end

    def find_or_create_value
      existing = active_tokens.order(:created_at).first
      existing ? existing.access_token : create[:access_token]
    end

    # Generates a new token and sets the old one's expiry. Only the partner's
    # newest active token can be rotated. When rotating, the oldest non-expired one is immediately expired
    def rotate(token_id, expires_at: nil)
      token = locked do
        old = find(token_id)
        active = active_tokens.order(:created_at, :id).to_a

        newest = active.last
        if old.id != newest.id
          raise AdminApi::Errors::Conflict, "API token #{old.id} isn't the newest API token for '#{@partner_id}' (#{newest.id} is); only the newest can be rotated"
        end

        if old.expires_at && active.any? { |t| t.expires_at.nil? }
          raise AdminApi::Errors::Conflict, "API token #{old.id} is already expiring and '#{@partner_id}' already has an API token without an expiry; it can't be rotated"
        end

        to_end = active.first([ active.size - MAX_ACTIVE + 1, 0 ].max)
        if to_end.any? { |t| t.expires_at.nil? }
          raise AdminApi::Errors::Conflict, "'#{@partner_id}' already has #{active.size} active API tokens; expire the extra ones before rotating"
        end

        new_expiry = if expires_at.present?
                       valid_expiry(expires_at)
                     elsif old.expires_at.nil?
                       valid_expiry(DEFAULT_GRACE_HOURS.hours.from_now)
                     end

        to_end.each { |t| t.update!(expires_at: Time.current) }
        new_token = old.user.api_access_tokens.create!
        old.update!(expires_at: new_expiry) if new_expiry
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
      # iso8601(3) keeps 3 fractional-second digits (milliseconds), e.g.
      # 2026-11-16T18:22:41.123Z; plain iso8601 would drop them.
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
