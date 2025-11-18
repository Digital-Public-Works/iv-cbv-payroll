namespace :weekly_reports do
  desc "Send weekly reports"
  task send_all: :environment do
    client_agency_config = Rails.application.config.client_agencies
    config = client_agency_config.client_agency_ids.each_with_object({}) do |id, hash|
      hash[id] = client_agency_config[id]
    end

    WeeklyReportDispatcher.new(
      config:       config,
      event_logger: GenericEventTracker.new
    ).send_weekly_summary_emails
  end
end
