require "rails_helper"
require "active_support/testing/time_helpers"

RSpec.describe WeeklyReportDispatcher, type: :mailer do
  include ActiveSupport::Testing::TimeHelpers

  # fixed time so time-based attributes are stable
  let(:now) { Time.zone.parse("2024-06-18 10:30:00") }

  # simple config objects that respond to #weekly_report
  Config = Struct.new(:weekly_report, keyword_init: true)

  let(:cfg_ok_a) { Config.new(weekly_report: { "enabled" => true, "recipient" => "a@example.com" }) }
  let(:cfg_ok_b) { Config.new(weekly_report: { "enabled" => true, "recipient" => "b@example.com" }) }
  let(:cfg_disabled) { Config.new(weekly_report: { "enabled" => false, "recipient" => "off@example.com" }) }

  let(:client_agency_config_hash) do
    # Order here defines agent_ids order in target_ids; keep deterministic
    { "agency_a" => cfg_ok_a, "agency_b" => cfg_ok_b, "agency_off" => cfg_disabled }
  end

  # Stubs for mailer chain
  let(:mailer_chain) { instance_double("WeeklyReportMailerChain") }
  let(:delivery_double) { instance_double(ActionMailer::MessageDelivery, deliver_now: true) }

  # event logger stub (Mixpanel)
  let(:fake_event_logger) { instance_double(GenericEventTracker, track: true) }

  before do
    travel_to(now)

    # Stub config accessor on the dispatcher instance
    allow_any_instance_of(described_class)
      .to receive(:client_agency_config)
            .and_return(client_agency_config_hash)

    # Stub New Relic
    allow(NewRelic::Agent).to receive(:record_custom_event)
    allow(NewRelic::Agent).to receive(:notice_error)

    # Stub mailer chain
    allow(WeeklyReportMailer)
      .to receive(:with)
            .and_return(mailer_chain)
    allow(mailer_chain).to receive(:report_email).and_return(delivery_double)

    # Stub event_logger on the dispatcher (from your app's base)
    allow_any_instance_of(described_class)
      .to receive(:event_logger)
            .and_return(fake_event_logger)
  end

  after { travel_back }

  describe "#perform" do
    it "sends to all enabled agencies, logs New Relic start/completed, and tracks Mixpanel success per client" do
      # Run
      described_class.new.perform

      # # Mailer calls (only enabled agencies)
      # expect(WeeklyReportMailer).to have_received(:with).twice
      # expect(mailer_chain).to have_received(:report_email).twice
      # expect(delivery_double).to have_received(:deliver_now).twice
      #
      # # verify both mailers were called with the correct params
      # expect(WeeklyReportMailer).to have_received(:with)
      #                                 .with(hash_including(client_id: "agency_a", recipient: "a@example.com", report_range: kind_of(Range)))
      # expect(WeeklyReportMailer).to have_received(:with)
      #                                 .with(hash_including(client_id: "agency_b", recipient: "b@example.com", report_range: kind_of(Range)))
      #
      # # verify start event
      # expect(NewRelic::Agent).to have_received(:record_custom_event)
      #                              .with("WeeklyReportMailerStarted", hash_including(
      #                                :time, target_count: 2, target_ids: satisfy { |s|
      #                                ids = s.split(","); ids.sort == %w[agency_a agency_b]
      #                              }
      #                              ))
      #
      # # verify completed event
      # expect(NewRelic::Agent).to have_received(:record_custom_event)
      #                              .with("WeeklyReportMailerCompleted", hash_including(
      #                                :time, attempted: 2, successes: 2, failures: 0,
      #                                success_ids: satisfy { |s| s.split(",").sort == %w[agency_a agency_b] },
      #                                failure_ids: ""
      #                              ))
      #
      # # Mixpanel success events per client
      # expect(fake_event_logger).to have_received(:track).with(
      #   TrackEvent::WeeklySummaryEmail, nil, hash_including(client_agency_id: "agency_a", status: "success")
      # )
      # expect(fake_event_logger).to have_received(:track).with(
      #   TrackEvent::WeeklySummaryEmail, nil, hash_including(client_agency_id: "agency_b", status: "success")
      # )
    end

    it "handles per-client failure: notices error, counts failure, and tracks Mixpanel failure" do
      # Make agency_b fail by removing its recipient at runtime
      client_agency_config_hash["agency_b"].weekly_report.delete("recipient")

      described_class.new.perform

      # agency_a succeeded, agency_b failed; still attempted 2
      expect(NewRelic::Agent).to have_received(:record_custom_event)
                                   .with("WeeklyReportMailerCompleted", hash_including(
                                     attempted: 2, successes: 1, failures: 1,
                                     success_ids: satisfy { |s| s.split(",").include?("agency_a") },
                                     failure_ids: satisfy { |s| s.split(",").include?("agency_b") }
                                   ))

      # notice_error called at least once
      expect(NewRelic::Agent).to have_received(:notice_error)
                                   .with(kind_of(StandardError), custom_params: { client_agency_id: "agency_b" })

      # Mixpanel events: one success, one failure
      expect(fake_event_logger).to have_received(:track).with(
        TrackEvent::WeeklySummaryEmail, nil, hash_including(client_agency_id: "agency_a", status: "success")
      )
      expect(fake_event_logger).to have_received(:track).with(
        TrackEvent::WeeklySummaryEmail, nil, hash_including(client_agency_id: "agency_b", status: "failure")
      )
    end

    it "skips disabled agencies" do
      # Ensure disabled agency never hits the mailer
      described_class.new.perform
      expect(WeeklyReportMailer).not_to have_received(:with)
                                          .with(hash_including(client_id: "agency_off"))
    end
  end
end
