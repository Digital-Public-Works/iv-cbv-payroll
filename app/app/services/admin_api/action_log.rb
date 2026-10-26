# log names of what was changed, not values
module AdminApi
  module ActionLog
    module_function

    def record(action:, actor:, partner_id:, result:, changed: [], **extra)
      fields = {
        action: action,
        actor: actor,
        env: ENV["DOMAIN_NAME"].presence || Rails.env,
        partner: partner_id,
        changed: Array(changed).join(","),
        result: result
      }.merge(extra)

      Rails.logger.info("admin_api #{fields.map { |k, v| "#{k}=#{v}" }.join(' ')}")
      NewRelic::Agent.record_custom_event("AdminApiAction", fields) if defined?(NewRelic::Agent)
    end
  end
end
