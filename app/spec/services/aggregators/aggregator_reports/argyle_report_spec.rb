require 'rails_helper'

RSpec.describe Aggregators::AggregatorReports::ArgyleReport, type: :service do
  include ArgyleApiHelper
  include Aggregators::ResponseObjects
  include ActiveSupport::Testing::TimeHelpers

  let(:account) { "abc123" }
  let!(:payroll_account) do
    create(:payroll_account, :argyle_fully_synced, aggregator_account_id: account)
  end
  let(:days_ago_to_fetch) { 90 }
  let(:days_ago_to_fetch_for_gig) { 90 }
  let(:today) { Date.today }
  let(:argyle_service) { Aggregators::Sdk::ArgyleService.new(:sandbox) }

  let(:identities_json) { argyle_load_relative_json_file('bob', 'request_identity.json') }
  let(:paystubs_json) { argyle_load_relative_json_file('bob', 'request_paystubs.json') }
  let(:gigs_json) { argyle_load_relative_json_file('bob', 'request_gigs.json') }
  let(:account_json) { argyle_load_relative_json_file('bob', 'request_account.json') }

  before do
    allow(argyle_service).to receive_messages(fetch_identities_api: identities_json, fetch_paystubs_api: paystubs_json, fetch_gigs_api: gigs_json, fetch_account_api: account_json)
  end

  around do |ex|
    Timecop.freeze(today, &ex)
  end

  describe "config.max_paystubs_per_account" do
    it "ships a deliberately high default so gig workers are not constrained" do
      expect(Rails.application.config.max_paystubs_per_account).to eq(1000)
    end
  end

  describe "#check_paystub_volume (anomalous-paystub-count guardrail)" do
    let(:report) do
      described_class.new(
        payroll_accounts: [ payroll_account ],
        argyle_service: argyle_service,
        days_to_fetch_for_w2: days_ago_to_fetch,
        days_to_fetch_for_gig: days_ago_to_fetch_for_gig
      )
    end

    let(:max_paystubs_per_account) { 10 }

    around do |ex|
      old_value = Rails.application.config.max_paystubs_per_account
      Rails.application.config.max_paystubs_per_account = max_paystubs_per_account
      ex.run
    ensure
      Rails.application.config.max_paystubs_per_account = old_value
    end

    before do
      report.instance_variable_set(:@fetched_days, 5)
      allow(Rails.logger).to receive(:error)
      allow(NewRelic::Agent).to receive(:notice_error)
    end

    it "surfaces an over-cap count to New Relic WITHOUT raising (report generation continues)" do
      over_cap = { "results" => Array.new(10) { {} } } # 10 >= cap(10) -> fires

      expect {
        report.send(:check_paystub_volume, over_cap, payroll_account)
      }.not_to raise_error

      expect(NewRelic::Agent).to have_received(:notice_error).with(
        an_instance_of(Aggregators::AggregatorReports::ArgyleReport::PaystubLimitExceededError),
        custom_params: hash_including(paystub_count: 10, max_paystubs: 10, lookback_days: 5)
      )
    end

    it "does nothing when the count is under the cap" do
      under_cap = { "results" => Array.new(3) { {} } } # 3 < cap(10)

      report.send(:check_paystub_volume, under_cap, payroll_account)

      expect(NewRelic::Agent).not_to have_received(:notice_error)
    end

    context "when the configured cap is disabled" do
      let(:max_paystubs_per_account) { nil }

      it "does not report regardless of the paystub count" do
        report.send(:check_paystub_volume, { "results" => Array.new(50_000) { {} } }, payroll_account)

        expect(NewRelic::Agent).not_to have_received(:notice_error)
      end
    end

    context "with the app's shipped default cap" do
      let(:max_paystubs_per_account) { 1000 }

      it "does not trip for a gig worker with many frequent cashouts" do
        report.send(:check_paystub_volume, { "results" => Array.new(999) { {} } }, payroll_account)

        expect(NewRelic::Agent).not_to have_received(:notice_error)
      end
    end
  end

  describe '#fetch_report_data' do
    let(:argyle_report) do
      described_class.new(
        payroll_accounts: [ payroll_account ],
        argyle_service: argyle_service,
        days_to_fetch_for_w2: days_ago_to_fetch,
        days_to_fetch_for_gig: days_ago_to_fetch_for_gig
      )
    end

    context "bob, a gig employee" do
      before do
        allow(argyle_service).to receive_messages(fetch_account_api: argyle_load_relative_json_file("bob", "request_account.json"), fetch_identities_api: argyle_load_relative_json_file("bob", "request_identity.json"), fetch_paystubs_api: argyle_load_relative_json_file("bob", "request_paystubs.json"))
        argyle_report.send(:fetch_report_data)
      end

      it 'calls the right APIs' do
        expect(argyle_service).to have_received(:fetch_identities_api).with(account: account)
        expect(argyle_service).to have_received(:fetch_paystubs_api).with(account: account, from_start_date: days_ago_to_fetch.days.ago, to_start_date: today)
      end

      it 'transforms response object correctly' do
        expect(argyle_report.identities).to all(be_an(Aggregators::ResponseObjects::Identity))
        expect(argyle_report.employments).to all(be_an(Aggregators::ResponseObjects::Employment))
        expect(argyle_report.incomes).to all(be_an(Aggregators::ResponseObjects::Income))
        expect(argyle_report.paystubs).to all(be_an(Aggregators::ResponseObjects::Paystub))
      end

      it 'does not have an employer address' do
        expect(argyle_report.employments.first.employer_address).to be_nil
      end

      it 'has an employment account_source' do
        expect(argyle_report.employments.first.account_source).to match(/argyle_sandbox/)
      end

      context "when in an agency configured to grab 182 days of gig data" do
        let(:days_ago_to_fetch_for_gig) { 182 }

        it "fetches 182 days" do
          expect(argyle_service).to have_received(:fetch_paystubs_api)
            .with(account: anything, from_start_date: 182.days.ago, to_start_date: Date.current)

          expect(argyle_report.from_date).to eq(182.days.ago)
          expect(argyle_report.to_date).to eq(Date.current)
        end
      end

      context 'when an error occurs' do
        before do
          allow(argyle_service).to receive(:fetch_identities_api).and_raise(StandardError.new('API error'))
        end

        it 'logs the error' do
          expect(Rails.logger).to receive(:error).with(/Report Fetch Error: API error/)
          expect { argyle_report.send(:fetch_report_data) }.to raise_error(StandardError, 'API error')
        end

        it 're-raises the error rather than swallowing it' do
          expect { argyle_report.send(:fetch_report_data) }.to raise_error(StandardError, 'API error')
        end
      end
    end

    context "joe, a W-2 employee" do
      before do
        allow(argyle_service).to receive_messages(fetch_identities_api: argyle_load_relative_json_file("joe", "request_identity.json"), fetch_paystubs_api: argyle_load_relative_json_file("joe", "request_paystubs.json"))
        argyle_report.send(:fetch_report_data)
      end

      it 'calls the right APIs' do
        expect(argyle_service).to have_received(:fetch_identities_api).with(account: account)
        expect(argyle_service).to have_received(:fetch_paystubs_api).with(account: account, from_start_date: days_ago_to_fetch.days.ago, to_start_date: today)
      end

      it 'transforms response objects correctly' do
        expect(argyle_report.identities).to all(be_an(Aggregators::ResponseObjects::Identity))
        expect(argyle_report.employments).to all(be_an(Aggregators::ResponseObjects::Employment))
        expect(argyle_report.incomes).to all(be_an(Aggregators::ResponseObjects::Income))
        expect(argyle_report.paystubs).to all(be_an(Aggregators::ResponseObjects::Paystub))
      end

      it 'has an employer address' do
        expect(argyle_report.employments.first.employer_address).to eq("202 Westlake Ave N, Seattle, WA 98109")
      end

      context "when in an agency configured to grab 182 days of gig data" do
        let(:days_ago_to_fetch_for_gig) { 182 }

        it "fetches only 90 days (because Joe is not a gig employee)" do
          expect(argyle_service).to have_received(:fetch_paystubs_api)
            .with(account: anything, from_start_date: 90.days.ago, to_start_date: Date.current)

          expect(argyle_report.from_date).to eq(90.days.ago)
          expect(argyle_report.to_date).to eq(Date.current)
        end
      end

      context 'when an error occurs' do
        before do
          allow(argyle_service).to receive(:fetch_identities_api).and_raise(StandardError.new('API error'))
        end

        it 'logs the error' do
          expect(Rails.logger).to receive(:error).with(/Report Fetch Error: API error/)
          expect { argyle_report.send(:fetch_report_data) }.to raise_error(StandardError, 'API error')
        end

        it 're-raises the error rather than swallowing it' do
          expect { argyle_report.send(:fetch_report_data) }.to raise_error(StandardError, 'API error')
        end
      end
    end


    describe "ArgylePaystubHours Mixpanel events" do
      let(:tracker_instance) { instance_double(GenericEventTracker, track: nil) }
      let(:w2_identity) { argyle_load_relative_json_file("joe", "request_identity.json")["results"].first }
      let(:w2_paystubs) { argyle_load_relative_json_file("joe", "request_paystubs.json")["results"] }

      before do
        allow(GenericEventTracker).to receive(:new).and_return(tracker_instance)
      end

      it "does not log paystub hours for a gig employment's paystubs" do
        allow(argyle_service).to receive_messages(fetch_identities_api: argyle_load_relative_json_file("bob", "request_identity.json"), fetch_paystubs_api: argyle_load_relative_json_file("bob", "request_paystubs.json"))

        argyle_report.send(:fetch_report_data)

        expect(tracker_instance).not_to have_received(:track)
          .with(TrackEvent::ArgylePaystubHours, any_args)
      end

      it "logs paystub hours for a W-2 employment's paystubs" do
        allow(argyle_service).to receive_messages(fetch_identities_api: argyle_load_relative_json_file("joe", "request_identity.json"), fetch_paystubs_api: { "results" => w2_paystubs })

        argyle_report.send(:fetch_report_data)

        expect(tracker_instance).to have_received(:track)
          .with(TrackEvent::ArgylePaystubHours, nil, anything)
          .exactly(w2_paystubs.size).times
      end

      it "logs only the W-2 paystubs when an account has both a gig and a W-2 employment" do
        gig_identity = w2_identity.merge("employment_type" => "contractor", "employment" => "gig-employment-id")
        gig_paystubs = w2_paystubs.first(3).each_with_index.map do |paystub, index|
          paystub.merge("id" => "gig-paystub-#{index}", "employment" => "gig-employment-id")
        end

        allow(argyle_service).to receive_messages(fetch_identities_api: { "results" => [ w2_identity, gig_identity ] }, fetch_paystubs_api: { "results" => w2_paystubs + gig_paystubs })

        argyle_report.send(:fetch_report_data)

        expect(tracker_instance).to have_received(:track)
          .with(TrackEvent::ArgylePaystubHours, nil, anything)
          .exactly(w2_paystubs.size).times
      end

      it "logs paystubs that carry no employment id, even on a gig-only account" do
        gig_identity = w2_identity.merge("employment_type" => "contractor")
        orphan_paystubs = w2_paystubs.first(2).map { |paystub| paystub.merge("employment" => nil) }

        allow(argyle_service).to receive_messages(fetch_identities_api: { "results" => [ gig_identity ] }, fetch_paystubs_api: { "results" => orphan_paystubs })

        argyle_report.send(:fetch_report_data)

        expect(tracker_instance).to have_received(:track)
          .with(TrackEvent::ArgylePaystubHours, nil, anything)
          .exactly(orphan_paystubs.size).times
      end
    end

    describe "Hours validations that trigger warnings" do
      {
        "high_hours_paystubs.json" => "hours outside expected range",
        "high_hours_gross_pay_list_paystubs.json" => "hours outside expected range in gross pay list"
      }.each do |fixture, reason|
        context "with #{reason} (#{fixture})" do
          before do
            allow(argyle_service).to receive(:fetch_paystubs_api)
              .and_return(argyle_load_relative_json_file("invalid_hours", fixture))

            allow(NewRelic::EventLogger).to receive(:track)
            argyle_report.send(:fetch_report_data)
          end

          it "generates a warning" do
            expect(argyle_report.warnings).not_to be_empty
          end

          it "includes the correct warning message" do
            expect(argyle_report.warnings[:hours].size).to eq(1)
            expect(argyle_report.warnings[:hours]).to include(match(/Invalid value received for hours/i))
          end

          it "sends a warning to New Relic" do
            expect(NewRelic::EventLogger).to have_received(:track).with(
              TrackEvent::ArgyleDataUnexpectedHours,
              hash_including(
                time: anything,
                cbv_flow_id: kind_of(Integer),
                warnings: a_string_matching(/Invalid value received for hours/i)
              )
            )
          end
        end
      end
    end

    describe "Hours validations that do not trigger warnings" do
      {
        "empty_hours_paystubs.json" => "empty hours",
        "null_hours_in_gross_pay_list_paystubs.json" => "null hours in gross pay list",
        "empty_hours_gross_pay_list_paystubs.json" => "empty hours in gross pay list",
        "negative_hours_paystubs.json" => "negative values",
        "negative_hours_gross_pay_list_paystubs.json" => "negative values in gross pay list"
      }.each do |fixture, reason|
        context "with #{reason} (#{fixture})" do
          before do
            allow(argyle_service).to receive(:fetch_paystubs_api)
              .and_return(argyle_load_relative_json_file("invalid_hours", fixture))

            allow(NewRelic::EventLogger).to receive(:track)
            argyle_report.send(:fetch_report_data)
          end

          it "does not generate a warning" do
            expect(argyle_report.warnings).to be_empty
          end

          it "does not send a warning to New Relic" do
            expect(NewRelic::EventLogger).not_to have_received(:track).with(
              anything,
              anything
            )
          end
        end
      end
    end

    describe '#fetch_gigs' do
      context "for Bob, a Uber driver" do
        before do
          allow(argyle_service).to receive_messages(fetch_identities_api: argyle_load_relative_json_file("bob", "request_identity.json"), fetch_paystubs_api: argyle_load_relative_json_file("bob", "request_paystubs.json"), fetch_gigs_api: argyle_load_relative_json_file("bob", "request_gigs.json"))
        end

        it 'returns an array of ResponseObjects::Gig' do
          argyle_report.send(:fetch_report_data)
          expect(argyle_report.gigs.length).to eq(50)

          expect(argyle_report.gigs[0]).to be_a(Aggregators::ResponseObjects::Gig)
        end

        it 'returns with expected attributes' do
          argyle_report.send(:fetch_report_data)
          expect(argyle_report.gigs[0]).to have_attributes(
                                             account_id: "019571bc-2f60-3955-d972-dbadfe0913a8",
                                             gig_type: "rideshare",
                                             gig_status: "cancelled",
                                             hours: nil,
                                             start_date: "2025-03-06",
                                             end_date: nil,
                                             mileage: 0.0,
                                             compensation_category: "work",
                                             compensation_amount: 0.0
          )
          expect(argyle_report.gigs[1]).to have_attributes(
                                             account_id: "019571bc-2f60-3955-d972-dbadfe0913a8",
                                             gig_type: "rideshare",
                                             gig_status: "completed",
                                             hours: 0.09,
                                             start_date: "2025-03-05",
                                             end_date: "2025-03-05",
                                             mileage: 8.29,
                                             compensation_category: "work",
                                             compensation_amount: 1024
          )
          expect(argyle_report.gigs[3]).to have_attributes(
                                             account_id: "019571bc-2f60-3955-d972-dbadfe0913a8",
                                             gig_type: "rideshare",
                                             gig_status: "completed",
                                             hours: 0.56,
                                             start_date: "2025-03-05",
                                             end_date: "2025-03-05",
                                             mileage: 12.31,
                                             compensation_category: "work",
                                             compensation_amount: 1945
          )
        end
      end
    end
  end

  describe '#fetch' do
    let(:argyle_report) do
      described_class.new(
        payroll_accounts: [ payroll_account ],
        argyle_service: argyle_service,
        days_to_fetch_for_w2: days_ago_to_fetch,
        days_to_fetch_for_gig: days_ago_to_fetch_for_gig
      )
    end

    def discarded_in_db?(record)
      PayrollAccount.with_discarded.find(record.id).discarded?
    end

    context "when Argyle returns an account" do
      it "does not discard the payroll_account" do
        argyle_report.fetch
        expect(discarded_in_db?(payroll_account)).to be false
      end

      it "still fetches report data" do
        argyle_report.fetch
        expect(argyle_service).to have_received(:fetch_identities_api).with(account: account)
      end
    end

    context "when Argyle does not return an account" do
      let(:other_account_id) { "missing-account-id" }

      let!(:other_payroll_account) do
        create(:payroll_account, :argyle_fully_synced, cbv_flow: payroll_account.cbv_flow, aggregator_account_id: other_account_id)
      end

      let(:argyle_report) do
        described_class.new(
          payroll_accounts: [ payroll_account, other_payroll_account ],
          argyle_service: argyle_service,
          days_to_fetch_for_w2: days_ago_to_fetch,
          days_to_fetch_for_gig: days_ago_to_fetch_for_gig
        )
      end

      before do
        allow(argyle_service).to receive(:fetch_account_api).with(account: account).and_return(account_json)
        allow(argyle_service).to receive(:fetch_account_api)
          .with(account: other_account_id)
          .and_raise(Faraday::ResourceNotFound.new(nil, nil))
      end

      it "discards the missing account and leaves the valid one alone" do
        argyle_report.fetch
        expect(discarded_in_db?(other_payroll_account)).to be true
        expect(discarded_in_db?(payroll_account)).to be false
      end

      it "removes the missing account from @payroll_accounts so its data is not fetched" do
        argyle_report.fetch
        expect(argyle_service).not_to have_received(:fetch_identities_api).with(account: other_account_id)
      end
    end

    context "when Argyle reports the account as disconnected" do
      let(:disconnected_account_json) do
        account_json.deep_dup.tap { |j| j["connection"]["status"] = "disconnected" }
      end

      before do
        allow(argyle_service).to receive(:fetch_account_api).and_return(disconnected_account_json)
      end

      it "discards the disconnected account" do
        expect { argyle_report.fetch }.to raise_error(Aggregators::AggregatorReports::ArgyleReport::NoValidAccountsError)
        expect(discarded_in_db?(payroll_account)).to be true
      end
    end

    context "when Argyle reports an error status" do
      let(:error_account_json) do
        account_json.deep_dup.tap { |j| j["connection"]["status"] = "error" }
      end

      before do
        allow(argyle_service).to receive(:fetch_account_api).and_return(error_account_json)
      end

      it "does not discard the account" do
        argyle_report.fetch
        expect(discarded_in_db?(payroll_account)).to be false
      end
    end

    context "when calling Argyle throws an error" do
      before do
        allow(argyle_service).to receive(:fetch_account_api).and_raise(StandardError, "argyle is down")
      end

      it "propagates the error rather than swallowing it, and does not discard the account" do
        expect { argyle_report.fetch }.to raise_error(StandardError, "argyle is down")
        expect(discarded_in_db?(payroll_account)).to be false
      end
    end

    context "when no accounts are connected" do
      before do
        allow(argyle_service).to receive(:fetch_account_api).and_raise(Faraday::ResourceNotFound.new(nil, nil))
      end

      it "raises NoValidAccountsError" do
        expect { argyle_report.fetch }.to raise_error(Aggregators::AggregatorReports::ArgyleReport::NoValidAccountsError)
      end

      it "discards the disconnected account and raises" do
        expect { argyle_report.fetch }.to raise_error(Aggregators::AggregatorReports::ArgyleReport::NoValidAccountsError)
        expect(discarded_in_db?(payroll_account)).to be true
      end
    end
  end

  describe "#days_since_last_paydate" do
    let(:argyle_report) do
      described_class.new(
        payroll_accounts: [ payroll_account ],
        argyle_service: argyle_service,
        days_to_fetch_for_w2: days_ago_to_fetch,
        days_to_fetch_for_gig: days_ago_to_fetch
      )
    end

    before do
      travel_to Time.new(2021, 4, 1, 0, 0, 0, "-04:00")
      allow(argyle_report)
        .to receive(:paystubs)
        .and_return(paystubs)
    end

    context "when no paystub date information is available" do
      let(:paystubs) do
        [ OpenStruct.new(pay_date: nil) ]
      end

      it "returns nil if no paystub date information available" do
        expect(argyle_report.days_since_last_paydate).to be_nil
      end
    end

    context "when the latest date is available" do
      let(:paystubs) do
        [ OpenStruct.new(pay_date: "2021-02-01"), OpenStruct.new(pay_date: "2021-03-02") ]
      end

      it "returns the latest date when dates available, compared to current time" do
        expect(argyle_report.days_since_last_paydate).to eq(30)
      end
    end
  end

  describe '#summarize_by_month' do
    context "bob, a gig employee" do
      let(:argyle_report) { described_class.new(
        payroll_accounts: [ payroll_account ],
        argyle_service: argyle_service,
        days_to_fetch_for_w2: days_ago_to_fetch,
        days_to_fetch_for_gig: days_ago_to_fetch) }

      let(:account) { "019571bc-2f60-3955-d972-dbadfe0913a8" }

      before do
        allow(argyle_service).to receive_messages(fetch_account_api: argyle_load_relative_json_file("bob", "request_account.json"), fetch_identities_api: argyle_load_relative_json_file("bob", "request_identity.json"), fetch_paystubs_api: argyle_load_relative_json_file("bob", "request_paystubs.json"))
        argyle_report.send(:fetch_report_data)
      end

      it "returns a hash of monthly totals" do
        monthly_summary_all_accounts = argyle_report.summarize_by_month(from_date: Date.parse("2025-01-08"), to_date: Date.parse("2025-03-31"))
        expect(monthly_summary_all_accounts.keys).to contain_exactly(account)

        monthly_summary = monthly_summary_all_accounts[account]
        expect(monthly_summary.keys).to contain_exactly("2025-03", "2025-02", "2025-01")

        march = monthly_summary["2025-03"]
        expect(march[:gigs].length).to eq(9)
        expect(march[:paystubs].length).to eq(1)
        expect(march[:accrued_gross_earnings]).to eq(3456) # in cents
        expect(march[:total_gig_hours]).to eq(3.61)
        expect(march[:total_mileage].round(2)).to eq(83.43)
        expect(march[:partial_month_range]).to an_object_eq_to({
                                                                 is_partial_month: true,
                                                                 description: "(Partial month: from Mar 1-Mar 6)",
                                                                 included_range_start: Date.parse("2025-03-01"),
                                                                 included_range_end: Date.parse("2025-03-06")
                                                               })

        feb = monthly_summary["2025-02"]
        expect(feb[:gigs].length).to eq(31)
        expect(feb[:paystubs].length).to eq(4)
        expect(feb[:accrued_gross_earnings]).to eq(23075) # in cents
        expect(feb[:total_gig_hours]).to eq(14.0)
        expect(feb[:total_mileage].round(2)).to eq(379.18)
        expect(feb[:partial_month_range]).to an_object_eq_to({
                                                               is_partial_month: false,
                                                               description: nil,
                                                               included_range_start: Date.parse("2025-02-01"),
                                                               included_range_end: Date.parse("2025-02-28")
                                                             })

        jan = monthly_summary["2025-01"]
        expect(jan[:gigs].length).to eq(0)
        expect(jan[:paystubs].length).to eq(5)
        expect(jan[:accrued_gross_earnings]).to eq(28237) # in cents
        expect(jan[:total_gig_hours]).to eq(0)
        expect(jan[:total_mileage]).to eq(0)
        expect(jan[:partial_month_range]).to an_object_eq_to({
                                                               is_partial_month: true,
                                                               description: "(Partial month: from Jan 2-Jan 31)",
                                                               included_range_start: Date.parse("2025-01-02"),
                                                               included_range_end: Date.parse("2025-01-31")
                                                             })
      end
    end

    context "busy_joe, an employee with multiple employments" do
      let(:account) { "01959b15-8b7f-5487-212d-2c0f50e3ec96" }
      let!(:payroll_account_2) do
        create(:payroll_account, :argyle_fully_synced, aggregator_account_id: account)
      end

      let(:argyle_report) { described_class.new(
        payroll_accounts: [ payroll_account_2 ],
        argyle_service: argyle_service,
        days_to_fetch_for_w2: days_ago_to_fetch,
        days_to_fetch_for_gig: days_ago_to_fetch) }

      let(:identities_json) { argyle_load_relative_json_file('busy_joe', 'request_identity.json') }
      let(:employments_json) { argyle_load_relative_json_file('busy_joe', 'request_employment.json') }
      let(:paystubs_json) { argyle_load_relative_json_file('busy_joe', 'request_paystubs.json') }
      let(:account_json) { argyle_load_relative_json_file('busy_joe', 'request_accounts.json') }

      before do
        allow(argyle_service).to receive_messages(fetch_identities_api: identities_json, fetch_employments_api: employments_json, fetch_paystubs_api: paystubs_json, fetch_account_api: account_json, fetch_gigs_api: { "results" => [] })
        argyle_report.fetch
      end

      it "returns a hash of monthly totals" do
        monthly_summary_all_accounts = argyle_report.summarize_by_month(from_date: Date.parse("2010-01-08"), to_date: Date.parse("2026-03-31"))

        expect(monthly_summary_all_accounts.keys).to contain_exactly(account)
        monthly_summary = monthly_summary_all_accounts[account]
        expect(monthly_summary.keys).to contain_exactly("2025-03")
        expect(monthly_summary["2025-03"][:paystubs].length).to eq(2)
      end
    end
  end

  describe 'valid fixture: valid identity, valid employer, gig worker, no paystubs' do
    let(:argyle_service) { instance_double(Aggregators::Sdk::ArgyleService) }
    let(:payroll_account) { create(:payroll_account, :argyle_fully_synced) }
    let(:argyle_report) do
      described_class.new(
        payroll_accounts: [ payroll_account ],
        argyle_service: argyle_service,
        days_to_fetch_for_w2: days_ago_to_fetch,
        days_to_fetch_for_gig: days_ago_to_fetch
      )
    end

    it 'A gig with valid identity and employer is valid even with no paystubs' do
      identities_json = argyle_load_relative_json_file('masked_prod_gig_validation_pass', 'request_identity.json')
      empty_response = { "results" => [] }

      allow(argyle_service).to receive_messages(fetch_identities_api: identities_json, fetch_paystubs_api: empty_response, fetch_account_api: empty_response, fetch_gigs_api: empty_response)

      argyle_report.fetch

      expect(argyle_report.valid?(:useful_report)).to be true

      expect(argyle_report.errors.full_messages).to be_empty
    end
  end
end
