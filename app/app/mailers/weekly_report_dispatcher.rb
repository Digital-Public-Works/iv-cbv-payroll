require "csv"
class WeeklyReportDispatcher < ApplicationMailer
  helper :view

  # Send email with a CSV file that reports on completed flows in the past week
  def perform
    # get today's date and then get the previous full week for the report send
    report_date = Time.zone.now.in_time_zone("America/New_York").beginning_of_week
    report_range = report_date.prev_week.all_week

    # iterate over all configured agencies to determine which agencies should receive the report
    enabled = client_agency_config.client_agency_ids.filter_map do |client_id|
      cfg = client_agency_config[client_id]
      [ client_id, cfg ] if cfg.weekly_report["enabled"]
    end.to_h
    agent_ids = enabled.map(&:first)

    # send newrelic event including how many we should send and which ones
    NewRelic::Agent.record_custom_event(
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
      begin
        recipient = cfg.weekly_report["recipient"] ||
                    raise("Missing `weekly_report.recipient` for #{client_id}")

        puts "Send to #{client_id} at #{recipient}"
        # One email per call = fresh mailer instance, isolated attachments
        WeeklyReportMailer
          .with(client_id:, report_range:, recipient:)
          .report_email
          .deliver_now

        success_ids << client_id
        Rails.logger.info("Weekly report sent for #{client_id} to #{recipient}")

        # send mixpanel event for success
        event_logger.track(TrackEvent::WeeklySummaryEmail, nil, {
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
        NewRelic::Agent.notice_error(e, custom_params: { client_agency_id: client_id })

        # send mixpanel event for failure
        event_logger.track(TrackEvent::WeeklySummaryEmail, nil, {
          client_agency_id: client_id,
          recipient: recipient,
          report_start: report_range.begin,
          report_end: report_range.end,
          status: "failure",
          time: Time.current.to_i
        })
      end
    end

    # record completed event with stats
    NewRelic::Agent.record_custom_event(
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
end
