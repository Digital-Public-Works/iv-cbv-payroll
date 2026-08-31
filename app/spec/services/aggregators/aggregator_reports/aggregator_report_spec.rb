require 'rails_helper'

RSpec.describe Aggregators::AggregatorReports::AggregatorReport, type: :service do
  context 'for pinwheel reports' do
    let(:report) { build(:pinwheel_report, :with_pinwheel_account) }

    describe '#total_gross_income' do
      it 'handles nil gross_pay_amount values' do
        report.paystubs = [
          Aggregators::ResponseObjects::Paystub.new(gross_pay_amount: 100),
          Aggregators::ResponseObjects::Paystub.new(gross_pay_amount: nil)
        ]

        expect { report.total_gross_income }.not_to raise_error
        expect(report.total_gross_income).to eq(100)
      end
    end

    describe '#summarize_by_employer' do
      it "returns nil for income, employment & identity when job succeeds but no data found" do
        account_id = report.payroll_accounts.first.aggregator_account_id

        allow(report.payroll_accounts.first).to receive(:job_succeeded?).with("income").and_return(false)
        allow(report.payroll_accounts.first).to receive(:job_succeeded?).with("employment").and_return(true)
        allow(report.payroll_accounts.first).to receive(:job_succeeded?).with("paystubs").and_return(false)
        allow(report.payroll_accounts.first).to receive(:job_succeeded?).with("identity").and_return(false)

        summary = report.summarize_by_employer
        expect(summary[account_id][:income]).to be_nil
        expect(summary[account_id][:identity]).to be_nil
        expect(summary[account_id][:has_employment_data]).to be_truthy
      end

      it "returns nil for income, employment & identity when job fails" do
        account_id = report.payroll_accounts.first.aggregator_account_id

        allow(report.payroll_accounts.first).to receive(:job_succeeded?).with("income").and_return(false)
        allow(report.payroll_accounts.first).to receive(:job_succeeded?).with("employment").and_return(false)
        allow(report.payroll_accounts.first).to receive(:job_succeeded?).with("paystubs").and_return(false)
        allow(report.payroll_accounts.first).to receive(:job_succeeded?).with("identity").and_return(false)

        summary = report.summarize_by_employer
        expect(summary[account_id][:income]).to be_nil
        expect(summary[account_id][:employment]).to be_nil
        expect(summary[account_id][:identity]).to be_nil
        expect(summary[account_id][:has_employment_data]).to be_falsy
      end
    end
  end

  context 'for argyle reports' do
    include ArgyleApiHelper
    include Aggregators::ResponseObjects
    include ActiveSupport::Testing::TimeHelpers

    let(:account) { "01959b15-8b7f-5487-212d-2c0f50e3ec96" }
    let!(:payroll_account) do
      create(:payroll_account, :argyle_fully_synced, aggregator_account_id: account)
    end
    let(:days_ago_to_fetch) { 90 }
    let(:days_ago_to_fetch_for_gig) { 90 }
    let(:today) { Date.today }
    let(:argyle_service) { Aggregators::Sdk::ArgyleService.new(:sandbox) }

    let(:identities_json) { argyle_load_relative_json_file('busy_joe', 'request_identity.json') }
    let(:employments_json) { argyle_load_relative_json_file('busy_joe', 'request_employment.json') }
    let(:paystubs_json) { argyle_load_relative_json_file('busy_joe', 'request_paystubs.json') }
    let(:account_json) { argyle_load_relative_json_file('busy_joe', 'request_accounts.json') }

    before do
      allow(argyle_service).to receive_messages(fetch_identities_api: identities_json, fetch_employments_api: employments_json, fetch_paystubs_api: paystubs_json, fetch_account_api: account_json, fetch_gigs_api: { "results" => [] })
    end

    around do |ex|
      Timecop.freeze(today, &ex)
    end

    describe '#summarize_by_employer' do
      let(:argyle_report) do
        Aggregators::AggregatorReports::ArgyleReport.new(
          payroll_accounts: [ payroll_account ],
          argyle_service: argyle_service,
          days_to_fetch_for_w2: days_ago_to_fetch,
          days_to_fetch_for_gig: days_ago_to_fetch_for_gig
        )
      end

      context "busy joe, an employee with multiple employments" do
        before do
          argyle_report.fetch
        end

        it 'selects the correct employer' do
          summary = argyle_report.summarize_by_employer
          expect(summary[account][:employment].employer_name).to eq("Aramark")
        end

        it 'filters to the correct paystubs for that employer' do
          summary = argyle_report.summarize_by_employer
          expect(summary[account][:paystubs].count).to eq(2)
          for paystub in summary[account][:paystubs]
            expect(paystub.employment_id).to eq(summary[account][:employment].employment_matching_id)
          end
        end

        it 'filters to the correct income for that employer' do
          summary = argyle_report.summarize_by_employer
          expect(summary[account][:income].employment_id).to eq(summary[account][:employment].employment_matching_id)
        end

        it 'filters to the correct identity for that employer' do
          summary = argyle_report.summarize_by_employer
          expect(summary[account][:identity].employment_id).to eq(summary[account][:employment].employment_matching_id)
        end

        it 'includes first_name and last_name from the identity' do
          summary = argyle_report.summarize_by_employer
          identity = summary[account][:identity]
          expect(identity.first_name).to eq("Joe")
          expect(identity.last_name).to eq("Burnam")
          expect(identity.full_name).to eq("Joe Burnam")
        end
      end
    end
  end

  describe '#income_report' do
    let(:comment) { "cool stuff" }
    let(:cbv_flow) { create(:cbv_flow, has_other_jobs: false, additional_information: { comment: comment }) }
    let(:report) { build(:pinwheel_report, :hydrated, :with_pinwheel_account) }

    before do
      report.payroll_accounts.first.cbv_flow = cbv_flow
    end

    it 'income information' do
      expect(report.income_report).to eq(
        has_other_jobs: false,
        paystub_images_included: false,
        employments: [
          {
            applicant_first_name: "Cool",
            applicant_last_name: "Guy",
            applicant_full_name: "Cool Guy",
            applicant_ssn: "XXX-XX-1234",
            applicant_extra_comments: "cool stuff",
            employer_name: "Cool Company",
            employer_phone: "604-555-1234",
            employer_address: "1234 Main St Vancouver BC V5K 0A1",
            employment_status: "inactive",
            employment_type: "gig",
            employment_start_date: Date.new(2014, 1, 1).iso8601,
            employment_end_date: Date.new(2014, 1, 2).iso8601,
            pay_frequency: "variable",
            compensation_amount: 100,
            compensation_unit: "hour",
            paystubs: [
              {
                pay_date: Date.new(2014, 1, 1).iso8601,
                pay_period_start: Date.new(2014, 1, 1),
                pay_period_end: Date.new(2014, 1, 2),
                pay_gross: 12345,
                pay_gross_ytd: 12345,
                pay_net: 12345,
                hours_paid: 12.0,
                direct_deposit_accounts: [],
                payout_card_accounts: []
              }
            ]
          }
        ]
      )
    end

    it 'does not raise when summary[:identity] is null' do
      existing_summary = report.summarize_by_employer
      account_id = existing_summary.keys.first
      existing_summary[account_id] = existing_summary[account_id].merge(
        identity: nil,
        has_identity_data: true
      )
      allow(report).to receive(:summarize_by_employer).and_return(existing_summary)

      expect { report.income_report }.not_to raise_error
      employment = report.income_report[:employments].first
      expect(employment[:applicant_first_name]).to be_nil
      expect(employment[:applicant_last_name]).to be_nil
      expect(employment[:applicant_full_name]).to be_nil
      expect(employment[:applicant_ssn]).to be_nil
      expect(employment[:employer_name]).to eq("Cool Company")
    end
  end

  describe '#paystub_images_included?' do
    let(:report) { build(:argyle_report, :with_argyle_account) }
    let(:agency_on)  { instance_double(ClientAgencyConfig::ClientAgency, include_paystubs: true) }
    let(:agency_off) { instance_double(ClientAgencyConfig::ClientAgency, include_paystubs: false) }

    def paystub(with_image:)
      Aggregators::ResponseObjects::Paystub.new(payroll_document_id: with_image ? "doc-1" : nil)
    end

    it 'is false when the agency does not have include_paystubs configured' do
      expect(report.paystub_images_included?(agency_off)).to be(false)
    end

    it 'is false when the agency is nil' do
      expect(report.paystub_images_included?(nil)).to be(false)
    end

    it 'is false when configured but no paystub has an image' do
      allow(report).to receive(:summarize_by_employer).and_return(
        "a" => { paystubs: [ paystub(with_image: false) ] },
        "b" => { paystubs: [] }
      )
      expect(report.paystub_images_included?(agency_on)).to be(false)
    end

    it 'is true when configured and at least one paystub has an image' do
      allow(report).to receive(:summarize_by_employer).and_return(
        "a" => { paystubs: [ paystub(with_image: false) ] },
        "b" => { paystubs: [ paystub(with_image: true) ] }
      )
      expect(report.paystub_images_included?(agency_on)).to be(true)
    end
  end

  describe '#employer_names_by_image_presence' do
    let(:report) { build(:argyle_report, :with_argyle_account) }

    def paystub(with_image:)
      Aggregators::ResponseObjects::Paystub.new(payroll_document_id: with_image ? "doc-1" : nil)
    end

    def employment(name)
      instance_double(Aggregators::ResponseObjects::Employment, employer_name: name)
    end

    it 'splits employers by image presence, preserving report order' do
      allow(report).to receive(:summarize_by_employer).and_return(
        "a" => { employment: employment("Aramark"), paystubs: [ paystub(with_image: true) ] },
        "b" => { employment: employment("Walmart"), paystubs: [ paystub(with_image: false) ] },
        "c" => { employment: employment("Target"),  paystubs: [] }
      )

      expect(report.employer_names_by_image_presence).to eq(
        with: %w[Aramark],
        without: %w[Walmart Target]
      )
    end

    it 'skips employers with a blank employer name' do
      allow(report).to receive(:summarize_by_employer).and_return(
        "a" => { employment: nil, paystubs: [ paystub(with_image: true) ] }
      )

      expect(report.employer_names_by_image_presence).to eq(with: [], without: [])
    end
  end
end
