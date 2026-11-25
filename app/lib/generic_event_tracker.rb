# The purpose of this class is to allow us to file events with multiple event providers at once
# If we no longer need to do this, it may be that this class has outlived its usefulness!
class GenericEventTracker
  # k6's default User-Agent, e.g. "Grafana k6/1.4.0 (https://k6.io/)" (older versions: "k6/0.x").
  K6_USER_AGENT = %r{\A(Grafana )?k6/}

  def track(event_type, request, attributes = {})
    return if load_test_traffic?(request, attributes) || bot_request?(request)

    merged_attributes = attributes.with_defaults(prep_request_attributes(request))
    if request.present?
      request_data = { headers: { "User-Agent": request.headers["User-Agent"] }, remote_ip: request.remote_ip }
    else
      request_data = nil
    end
    MixpanelEventTrackingJob.perform_later(event_type, request_data, merged_attributes)
  rescue => ex
    Rails.logger.error "Unable to track event (#{event_type}): #{ex}, line: #{ex.backtrace&.first}"
    raise unless Rails.env.production?
  end

  private

  # don't log load test traffic
  def load_test_traffic?(request, attributes)
    return true if request.present? && K6_USER_AGENT.match?(request.headers["User-Agent"].to_s)

    device_id = attributes[:device_id] || attributes["device_id"]
    device_id.present? && device_id == Api::LoadTestSessionsController::LOAD_TEST_DEVICE_ID
  end

  # don't log bot requests
  def bot_request?(request)
    return false if request.blank?

    user_agent = request.headers["User-Agent"]
    user_agent.present? && DeviceDetector.new(user_agent).bot?
  end

  def prep_request_attributes(request)
    defaults = { time: Time.now.to_i }
    if request.present?
      url_params = request.params.slice("client_agency_id", "locale")

      defaults = defaults.merge({
        # Not setting device_id because Mixpanel fixates on that as the distinct_id, which we do not want
        ip: request.remote_ip,
        cbv_flow_id: request.session[:cbv_flow_id],
        client_agency_id: url_params["client_agency_id"],
        locale: url_params["locale"] || I18n.locale.to_s,
        user_agent: request.headers["User-Agent"]
      })
    end
    defaults
  end
end
