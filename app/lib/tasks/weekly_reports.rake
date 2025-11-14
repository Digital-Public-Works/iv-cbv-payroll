namespace :weekly_reports do
  desc "Send weekly reports"
  task send_all: :environment do

    WeeklyReportDispatcher
      .perform
  end
end
