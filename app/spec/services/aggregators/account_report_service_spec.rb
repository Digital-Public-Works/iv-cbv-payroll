require 'rails_helper'

RSpec.describe Aggregators::AccountReportService do
  include ArgyleApiHelper

  let(:cbv_flow) { create(:cbv_flow, :invited) }
  let(:argyle_service) { Aggregators::Sdk::ArgyleService.new("sandbox") }

  describe '#validate' do
    context 'with valid report data (sarah fixture)' do
      let(:account_id) { '01956d5f-cb8d-af2f-9232-38bce8531f58' }
      let!(:payroll_account) do
        create(
          :payroll_account,
          :argyle_fully_synced,
          cbv_flow: cbv_flow,
          aggregator_account_id: account_id
        )
      end
      let(:report) do
        Aggregators::AggregatorReports::ArgyleReport.new(
          payroll_accounts: [ payroll_account ],
          argyle_service: argyle_service,
          days_to_fetch_for_w2: 90,
          days_to_fetch_for_gig: 90
        )
      end

      before do
        argyle_stub_request_identities_response("sarah")
        argyle_stub_request_paystubs_response("sarah")
        argyle_stub_request_gigs_response("sarah")
        argyle_stub_request_account_response("sarah")
        report.fetch
      end

      it 'returns a valid result' do
        service = described_class.new(report, payroll_account)
        result = service.validate

        expect(result).to be_valid
        expect(result.account_report).to be_present
        expect(result.errors).to be_empty
      end

      it 'returns the account_report with employment data' do
        service = described_class.new(report, payroll_account)
        result = service.validate

        expect(result.account_report.employment).to be_present
        expect(result.account_report.employment.employer_name).to eq("Whole Foods")
      end
    end

    context 'with empty report data (no identity records)' do
      let(:account_id) { 'empty-account-id' }
      let!(:payroll_account) do
        create(
          :payroll_account,
          :argyle_fully_synced,
          cbv_flow: cbv_flow,
          aggregator_account_id: account_id
        )
      end
      let(:report) do
        Aggregators::AggregatorReports::ArgyleReport.new(
          payroll_accounts: [ payroll_account ],
          argyle_service: argyle_service,
          days_to_fetch_for_w2: 90,
          days_to_fetch_for_gig: 90
        )
      end

      before do
        argyle_stub_request_identities_response("empty")
        argyle_stub_request_paystubs_response("empty")
        argyle_stub_request_gigs_response("empty")
        argyle_stub_request_account_response("empty")
        report.fetch
      end

      it 'returns an invalid result' do
        service = described_class.new(report, payroll_account)
        result = service.validate

        expect(result).not_to be_valid
        expect(result.account_report).to be_present
      end

      it 'includes validation errors' do
        service = described_class.new(report, payroll_account)
        result = service.validate

        expect(result.errors).not_to be_empty
        expect(result.error_messages).to include("No employments present")
      end

      it 'returns nil employment in the account_report' do
        service = described_class.new(report, payroll_account)
        result = service.validate

        expect(result.account_report.employment).to be_nil
      end
    end

    context 'with an invalid report' do
      let(:account_id) { 'empty-account-id' }
      let!(:payroll_account) do
        create(
          :payroll_account,
          :argyle_fully_synced,
          cbv_flow: cbv_flow,
          aggregator_account_id: account_id
        )
      end
      let(:report) do
        Aggregators::AggregatorReports::ArgyleReport.new(
          payroll_accounts: [ payroll_account ],
          argyle_service: argyle_service,
          days_to_fetch_for_w2: 90,
          days_to_fetch_for_gig: 90
        )
      end

      before do
        argyle_stub_request_identities_response("empty")
        argyle_stub_request_paystubs_response("empty")
        argyle_stub_request_gigs_response("empty")
        argyle_stub_request_account_response("empty")
        report.fetch
      end

      it 'sends an event to New Relic' do
        expect(NewRelic::Agent).to receive(:record_custom_event).with(
          TrackEvent::ApplicantReportAttemptedUsefulRequirements,
          {
            time: anything,
            cbv_applicant_id: cbv_flow.cbv_applicant_id,
            cbv_flow_id: payroll_account.cbv_flow_id,
            device_id: cbv_flow.device_id,
            invitation_id: cbv_flow.cbv_flow_invitation_id
          }
        )

        expect(NewRelic::Agent).to receive(:record_custom_event).with(
          TrackEvent::ApplicantReportFailedUsefulRequirements,
          {
            time: anything,
            cbv_applicant_id: cbv_flow.cbv_applicant_id,
            cbv_flow_id: payroll_account.cbv_flow_id,
            device_id: cbv_flow.device_id,
            invitation_id: cbv_flow.cbv_flow_invitation_id,
            errors: "Identities No identities present, Employments No employments present"
          }
        )

        service = described_class.new(report, payroll_account)
        result = service.validate

        expect(result.errors).not_to be_empty
      end
    end

    context 'with mismatched account_id' do
      let(:account_id) { 'wrong-account-id' }
      let!(:payroll_account) do
        create(
          :payroll_account,
          :argyle_fully_synced,
          cbv_flow: cbv_flow,
          aggregator_account_id: account_id
        )
      end
      let(:report) do
        Aggregators::AggregatorReports::ArgyleReport.new(
          payroll_accounts: [ payroll_account ],
          argyle_service: argyle_service,
          days_to_fetch_for_w2: 90,
          days_to_fetch_for_gig: 90
        )
      end

      before do
        # Use bob's fixtures but payroll_account has wrong ID
        argyle_stub_request_identities_response("bob")
        argyle_stub_request_paystubs_response("bob")
        argyle_stub_request_gigs_response("bob")
        argyle_stub_request_account_response("bob")
        report.fetch
      end

      it 'returns an invalid result when account_id does not match any employments' do
        service = described_class.new(report, payroll_account)
        result = service.validate

        expect(result).not_to be_valid
        expect(result.error_messages).to include("No employments present")
      end
    end
  end

  describe Aggregators::AccountReportService::ValidationResult do
    let(:mock_errors) { double("errors", full_messages: [ "Error 1", "Error 2" ], empty?: false) }
    let(:mock_account_report) { double("account_report") }

    describe '#valid?' do
      it 'returns true when valid' do
        result = described_class.new(account_report: mock_account_report, valid: true, errors: mock_errors)
        expect(result.valid?).to be true
      end

      it 'returns false when invalid' do
        result = described_class.new(account_report: mock_account_report, valid: false, errors: mock_errors)
        expect(result.valid?).to be false
      end
    end

    describe '#error_messages' do
      it 'joins error messages with comma' do
        result = described_class.new(account_report: mock_account_report, valid: false, errors: mock_errors)
        expect(result.error_messages).to eq("Error 1, Error 2")
      end
    end
  end
end
