require "rails_helper"
require "active_support/testing/time_helpers"

RSpec.describe WeeklyReportDispatcher, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.parse("2025-11-18 10:30:00") }

  Config = Struct.new(:weekly_report, :timezone, keyword_init: true)

  let(:cfg_ok_a) do
    Config.new(
      weekly_report: { "enabled" => true, "recipient" => "a@example.com" },
      timezone: "America/New_York"
    )
  end

  let(:cfg_ok_b) do
    Config.new(
      weekly_report: { "enabled" => true, "recipient" => "b@example.com" },
      timezone: "America/Los_Angeles"
    )
  end

  let(:cfg_disabled) do
    Config.new(
      weekly_report: { "enabled" => false, "recipient" => "off@example.com" },
      timezone: "America/Chicago"
    )
  end

  let(:client_agency_config_hash) do
    { "agency_a" => cfg_ok_a, "agency_b" => cfg_ok_b, "agency_off" => cfg_disabled }
  end

  let(:mailer_chain)    { instance_double("WeeklyReportMailerChain") }
  let(:delivery_double) { instance_double(ActionMailer::MessageDelivery, deliver_now: true) }

  let(:fake_event_logger) { instance_double(GenericEventTracker, track: true) }

  let(:clock) { -> { now } }

  let(:dispatcher) do
    described_class.new(
      config:       client_agency_config_hash,
      event_logger: fake_event_logger,
      clock:        clock
    )
  end

  before do
    travel_to(now)

    allow(NewRelic::Agent).to receive(:record_custom_event)
    allow(NewRelic::Agent).to receive(:notice_error)

    allow(WeeklyReportMailer).to receive(:with).and_return(mailer_chain)
    allow(mailer_chain).to receive(:report_email).and_return(delivery_double)
  end

  after { travel_back }

  describe "#send_weekly_summary_emails" do
    it "passes last full week as report_range" do
      captured_ranges = []
      allow(WeeklyReportMailer).to receive(:with) do |args|
        captured_ranges << args[:report_range]
        mailer_chain
      end

      dispatcher.send_weekly_summary_emails

      expect(captured_ranges.size).to eq(2)

      captured_ranges.each do |r|
        # Given now = 2025-11-18 10:30, with Monday as beginning_of_week:
        # report_date = 2025-11-17 00:00:00
        # prev_week = 2025-11-10..2025-11-16

        expect(r.begin.to_date).to eq(Date.new(2025, 11, 10))
        expect(r.end.to_date).to   eq(Date.new(2025, 11, 16))
      end
    end

    it "sends to all enabled agencies, logs New Relic start/completed, and tracks Mixpanel success per client" do
      dispatcher.send_weekly_summary_emails

      # Mailer calls (only enabled agencies)
      expect(WeeklyReportMailer).to have_received(:with).twice
      expect(mailer_chain).to have_received(:report_email).twice
      expect(delivery_double).to have_received(:deliver_now).twice

      # verify both mailers were called with the correct params
      expect(WeeklyReportMailer).to have_received(:with)
                                      .with(hash_including(client_id: "agency_a", recipient: "a@example.com", report_range: kind_of(Range)))
      expect(WeeklyReportMailer).to have_received(:with)
                                      .with(hash_including(client_id: "agency_b", recipient: "b@example.com", report_range: kind_of(Range)))

      # verify start event
      expect(NewRelic::Agent).to have_received(:record_custom_event)
                                   .with("WeeklyReportMailerStarted", hash_including(
                                     :time,
                                     target_count: 2,
                                     target_ids: satisfy { |s| s.split(",").sort == %w[agency_a agency_b] }
                                   ))

      # verify completed event
      expect(NewRelic::Agent).to have_received(:record_custom_event)
                                   .with("WeeklyReportMailerCompleted", hash_including(
                                     :time,
                                     attempted: 2, successes: 2, failures: 0,
                                     success_ids: satisfy { |s| s.split(",").sort == %w[agency_a agency_b] },
                                     failure_ids: ""
                                   ))

      # Mixpanel success events per client
      expect(fake_event_logger).to have_received(:track).with(
        TrackEvent::WeeklySummaryEmail, nil, hash_including(client_agency_id: "agency_a", status: "success")
      )
      expect(fake_event_logger).to have_received(:track).with(
        TrackEvent::WeeklySummaryEmail, nil, hash_including(client_agency_id: "agency_b", status: "success")
      )
    end

    it "handles per-client failure: notices error, counts failure, and tracks Mixpanel failure" do
      # Make agency_b fail by removing its recipient at runtime
      client_agency_config_hash["agency_b"].weekly_report.delete("recipient")

      dispatcher.send_weekly_summary_emails

      # agency_a succeeded, agency_b failed; still attempted 2
      expect(NewRelic::Agent).to have_received(:record_custom_event)
                                   .with("WeeklyReportMailerCompleted", hash_including(
                                     attempted: 2, successes: 1, failures: 1,
                                     success_ids: satisfy { |s| s.split(",").include?("agency_a") },
                                     failure_ids: satisfy { |s| s.split(",").include?("agency_b") }
                                   ))

      expect(NewRelic::Agent).to have_received(:notice_error)
                                   .with(kind_of(StandardError), custom_params: { client_agency_id: "agency_b" })

      # mixpanel
      expect(fake_event_logger).to have_received(:track).with(
        TrackEvent::WeeklySummaryEmail, nil, hash_including(client_agency_id: "agency_a", status: "success")
      )
      expect(fake_event_logger).to have_received(:track).with(
        TrackEvent::WeeklySummaryEmail, nil, hash_including(client_agency_id: "agency_b", status: "failure")
      )
    end

    it "only calls mailer for enabled agencies" do
      dispatcher.send_weekly_summary_emails

      expect(WeeklyReportMailer).to have_received(:with).twice
      expect(WeeklyReportMailer).not_to have_received(:with)
                                          .with(hash_including(client_id: "agency_off"))
    end

    it "counts deliver_now errors as failures and still completes" do
      allow(delivery_double).to receive(:deliver_now)
                                  .and_raise(StandardError, "smtp failed")

      dispatcher.send_weekly_summary_emails

      expect(NewRelic::Agent).to have_received(:record_custom_event)
                                   .with("WeeklyReportMailerCompleted", hash_including(
                                     attempted: 2, successes: 0, failures: 2
                                   ))
      expect(NewRelic::Agent).to have_received(:notice_error).at_least(:once)
      expect(fake_event_logger).to have_received(:track)
                                     .with(TrackEvent::WeeklySummaryEmail, nil, hash_including(status: "failure"))
                                     .at_least(:once)
    end

    it "handles zero-enabled agencies (no-ops cleanly)" do
      client_agency_config_hash.each_value { |c| c.weekly_report["enabled"] = false }

      dispatcher.send_weekly_summary_emails

      expect(WeeklyReportMailer).not_to have_received(:with)
      expect(NewRelic::Agent).to have_received(:record_custom_event)
                                   .with("WeeklyReportMailerStarted", hash_including(target_count: 0, target_ids: ""))
      expect(NewRelic::Agent).to have_received(:record_custom_event)
                                   .with("WeeklyReportMailerCompleted", hash_including(
                                     attempted: 0, successes: 0, failures: 0, success_ids: "", failure_ids: ""
                                   ))
    end

    it "emits deterministic target_ids order" do
      dispatcher.send_weekly_summary_emails

      expect(NewRelic::Agent).to have_received(:record_custom_event)
                                   .with("WeeklyReportMailerStarted", hash_including(
                                     target_ids: "agency_a,agency_b"
                                   ))
    end

    it "emits exactly one Mixpanel success per enabled client" do
      dispatcher.send_weekly_summary_emails

      expect(fake_event_logger).to have_received(:track)
                                     .with(TrackEvent::WeeklySummaryEmail, nil, hash_including(client_agency_id: "agency_a", status: "success"))
                                     .once
      expect(fake_event_logger).to have_received(:track)
                                     .with(TrackEvent::WeeklySummaryEmail, nil, hash_including(client_agency_id: "agency_b", status: "success"))
                                     .once
    end

    it "computes report_range using each agency's configured timezone" do
      ranges_by_client = {}

      # Capture the report_range per client_id
      allow(WeeklyReportMailer).to receive(:with) do |args|
        ranges_by_client[args[:client_id]] = args[:report_range]
        mailer_chain
      end

      dispatcher.send_weekly_summary_emails

      ny_range = ranges_by_client["agency_a"]
      la_range = ranges_by_client["agency_b"]

      expect(ny_range).to be_a(Range)
      expect(la_range).to be_a(Range)

      # Given now = 2025-11-18 10:30, with Monday as beginning_of_week:
      # report_date (per tz) = 2025-11-17 00:00 local
      # prev_week = 2025-11-10..2025-11-16 in each timezone

      # agency_a — America/New_York
      expect(ny_range.begin.in_time_zone("America/New_York").to_date).to eq(Date.new(2025, 11, 10))
      expect(ny_range.end.in_time_zone("America/New_York").to_date).to   eq(Date.new(2025, 11, 16))
      expect(ny_range.begin.in_time_zone("America/New_York").hour).to    eq(0)

      # agency_b — America/Los_Angeles
      expect(la_range.begin.in_time_zone("America/Los_Angeles").to_date).to eq(Date.new(2025, 11, 10))
      expect(la_range.end.in_time_zone("America/Los_Angeles").to_date).to   eq(Date.new(2025, 11, 16))
      expect(la_range.begin.in_time_zone("America/Los_Angeles").hour).to    eq(0)

      # And they should have different UTC offsets (different timezones)
      expect(ny_range.begin.utc_offset).not_to eq(la_range.begin.utc_offset)
    end
  end
end
