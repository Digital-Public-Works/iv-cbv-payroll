module NonProductionAccessible
  extend ActiveSupport::Concern

  # Returns true if running in development, test, or demo environment
  # Use this to gate features that should only be available in non-production environments
  def non_production_mode?
    Rails.env.development? || Rails.env.test? || ENV["DOMAIN_NAME"] == "demo.divt.app"
  end
end
