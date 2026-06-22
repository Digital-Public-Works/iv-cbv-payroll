# frozen_string_literal: true

# Partner configs are loaded lazily per request (see ClientAgencyConfig), so
# nothing is loaded into memory at boot. We still run a single validation pass at
# boot to surface any misconfigured partner early — partner configs change
# rarely, so this is a cheap diagnostic, not a serving cost. It only logs
# warnings (it never raises), so one broken partner can't take down boot. Live
# requests independently re-validate the specific partner being served (see
# ClientAgencyConfig#build_agency), so partners changed after boot are still
# caught.
#
# Skipped in the test environment, where validation is exercised directly in
# specs and a boot-time pass would only add log noise.
Rails.application.config.after_initialize do
  next if Rails.env.test?

  begin
    ClientAgencyConfig.instance.validate_all
  rescue => e
    Rails.logger.warn("Skipped partner config validation at boot: #{e.message}")
  end
end
