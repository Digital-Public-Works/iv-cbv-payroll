# Environment configuration for the partner-config admin API (`/api/admin/v1`).
module AdminApi
  module Config
    # does the api 'exist' as far as routes at all? if blank. it does not. Also the key used to sign requests
    SERVICE_SECRET_VAR = "ADMIN_API_SERVICE_SECRET"
    # per environment 'can the settings be edited directly'. default `true` in demo and `false` in prod
    SETTINGS_WRITABLE_VAR = "ADMIN_API_SETTINGS_WRITABLE"

    def self.enabled?
      service_secret.present?
    end

    def self.service_secret
      ENV[SERVICE_SECRET_VAR].presence
    end

    # Only an explicit "true" makes settings writable. An environment that
    # forgets the flag behaves like prod (read-only settings), never like demo.
    def self.settings_writable?
      ENV[SETTINGS_WRITABLE_VAR].to_s.strip.casecmp?("true")
    end
  end
end
