require "csv"
class WeeklyReportDispatcher
  # config is an instance of AgencyConfig, turned into a hash. See weekly_reports.rake for where this is used
  def initialize(config:, event_logger:, nr: NewRelic::Agent, clock: -> { Time.current })
    @config       = config
    @event_logger = event_logger
    @nr           = nr
    @clock        = clock                   # injectable clock for deterministic tests
  end

  # send email to all enabled agencies for the last full week
  def send_weekly_summary_emails
    # 1) Get enabled agencies safely from a Hash-like config
    enabled = enabled_clients(@config)
    agent_ids = enabled.keys

    # send newrelic event including how many we should send and which ones
    @nr.record_custom_event(
      "WeeklyReportMailerStarted",
      {
        time: Time.current.to_i,
        target_count: agent_ids.size,
        target_ids: agent_ids.join(",")
      }
    )

    success_ids = []
    failure_ids = []

    enabled.each do |client_id, cfg|
      recipient, report_range = nil, nil
      begin
        recipient = fetch_recipient!(cfg, client_id)
        report_range = compute_last_full_week_for(cfg)

        # One email per call = fresh mailer instance, isolated attachments
        WeeklyReportMailer
          .with(client_id:, report_range:, recipient:)
          .report_email
          .deliver_now

        success_ids << client_id
        Rails.logger.info("Weekly report sent for #{client_id} to #{recipient}")

        # send mixpanel event for success
        @event_logger.track(TrackEvent::WeeklySummaryEmail, nil, {
          client_agency_id: client_id,
          recipient: recipient,
          report_start: report_range.begin,
          report_end: report_range.end,
          status: "success",
          time: Time.current.to_i
        })

      rescue => e
        failure_ids << client_id
        Rails.logger.error("Weekly report FAILED for #{client_id}: #{e.class} - #{e.message}")
        @nr.notice_error(e, custom_params: { client_agency_id: client_id })

        # send mixpanel event for failure
        @event_logger.track(TrackEvent::WeeklySummaryEmail, nil, {
          client_agency_id: client_id,
          recipient: recipient,
          report_start: report_range&.begin,
          report_end: report_range&.end,
          status: "failure",
          time: Time.current.to_i
        })
      end
    end

    # record completed event with stats
    @nr.record_custom_event(
      "WeeklyReportMailerCompleted",
      {
        time: Time.current.to_i,
        attempted: agent_ids.size,
        successes: success_ids.size,
        failures: failure_ids.size,
        success_ids: success_ids.join(","),
        failure_ids: failure_ids.join(",")
      }
    )
  end

  private
  def enabled_clients(config)
    config
      .select { |_id, cfg| cfg.weekly_report["enabled"] }
      .sort_by { |id, _| id } # sort for specific order, helps with spec
      .to_h
  end

  def fetch_recipient!(cfg, client_id)
    cfg.weekly_report["recipient"] || raise("No weekly report recipients configured for for #{client_id}")
  end

  def compute_last_full_week_for(cfg)
    tz = cfg.timezone
    now = @clock.call
    report_date  = tz ? now.in_time_zone(tz).beginning_of_week : now.beginning_of_week
    report_date.prev_week.all_week
  end
end
