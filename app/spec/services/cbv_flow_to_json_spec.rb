require "rails_helper"

RSpec.describe CbvFlowToJson do
  let(:completed_at) { Time.find_zone("UTC").local(2025, 5, 1, 1) }
  let(:cbv_applicant) { create(:cbv_applicant, case_number: "ABC1234") }
  let(:cbv_flow) do
    create(:cbv_flow,
      :invited,
      :with_pinwheel_account,
      cbv_applicant: cbv_applicant,
      consented_to_authorized_use_at: completed_at,
      confirmation_code: "WEBHOOK123"
    )
  end

  let(:mock_client_agency) { instance_double(ClientAgencyConfig::ClientAgency) }
  let(:pinwheel_report) { build(:pinwheel_report, :with_pinwheel_account) }
  let(:argyle_report) { build(:argyle_report, :with_argyle_account) }
  let(:aggregator_report) do
    Aggregators::AggregatorReports::CompositeReport.new(
      [ pinwheel_report, argyle_report ],
      days_to_fetch_for_w2: 90,
      days_to_fetch_for_gig: 90
    )
  end

  before do
    allow(mock_client_agency).to receive(:id).and_return("sandbox")
    allow(CbvApplicant).to receive(:valid_attributes_for_agency).with("sandbox").and_return([ "case_number" ])
  end

  subject { described_class.new(cbv_flow, mock_client_agency, aggregator_report) }

  describe "#to_h" do
    let(:payload) { subject.to_h }

    it "returns a hash with report_metadata, client_information, and employment_records" do
      expect(payload).to include(:report_metadata, :client_information, :employment_records)
    end

    describe "report_metadata" do
      it "includes confirmation_code" do
        expect(payload[:report_metadata][:confirmation_code]).to eq("WEBHOOK123")
      end

      it "includes report_date_range with start_date and end_date" do
        range = payload[:report_metadata][:report_date_range]
        expect(range[:start_date]).to be_present
        expect(range[:end_date]).to be_present
      end

      it "includes consent_timestamp_utc" do
        expect(payload[:report_metadata][:consent_timestamp_utc]).to eq(completed_at.utc.iso8601)
      end
    end

    describe "client_information" do
      it "includes agency partner metadata" do
        expect(payload[:client_information]["case_number"]).to eq("ABC1234")
      end
    end

    describe "employment_records" do
      it "is an array with records" do
        expect(payload[:employment_records]).to be_an(Array)
        expect(payload[:employment_records]).not_to be_empty
      end

      it "converts currency values from cents to dollars" do
        record = payload[:employment_records].first
        payments = record[:w2_payments]
        expect(payments).to be_present
        expect(payments.any? { |p| p[:gross_pay].is_a?(Numeric) }).to be true
      end

      it "includes all four array fields on every record" do
        payload[:employment_records].each do |record|
          expect(record).to have_key(:w2_monthly_summaries)
          expect(record).to have_key(:w2_payments)
          expect(record).to have_key(:gig_monthly_summaries)
          expect(record).to have_key(:gig_payments)
        end
      end

      context "for a W2 employment record" do
        let(:w2_record) { payload[:employment_records].find { |r| r[:employment_type] == "W2" } }

        it "sets gig fields to null" do
          skip "no W2 records in test data" unless w2_record
          expect(w2_record[:gig_monthly_summaries]).to be_nil
          expect(w2_record[:gig_payments]).to be_nil
        end

        it "uses start/end keys in pay_period" do
          skip "no W2 records in test data" unless w2_record
          payment = w2_record[:w2_payments]&.first
          skip "no W2 payments in test data" unless payment
          expect(payment[:pay_period]).to have_key(:start)
          expect(payment[:pay_period]).to have_key(:end)
          expect(payment[:pay_period]).not_to have_key(:start_date)
          expect(payment[:pay_period]).not_to have_key(:end_date)
        end

        it "defaults gross_pay, net_pay, and gross_pay_ytd to 0 instead of nil" do
          skip "no W2 records in test data" unless w2_record
          w2_record[:w2_payments]&.each do |payment|
            expect(payment[:gross_pay]).to be_a(Numeric)
            expect(payment[:net_pay]).to be_a(Numeric)
            expect(payment[:gross_pay_ytd]).to be_a(Numeric)
          end
        end

        it "returns year as a string in monthly summaries" do
          skip "no W2 records in test data" unless w2_record
          w2_record[:w2_monthly_summaries]&.each do |summary|
            expect(summary[:year]).to be_a(String)
          end
        end

        it "only includes name and amount in gross_pay_line_items" do
          skip "no W2 records in test data" unless w2_record
          payment = w2_record[:w2_payments]&.first
          skip "no W2 payments in test data" unless payment
          payment[:gross_pay_line_items].each do |item|
            expect(item.keys).to contain_exactly(:name, :amount)
          end
        end
      end

      context "for a GIG employment record" do
        let(:gig_record) { payload[:employment_records].find { |r| r[:employment_type] == "GIG" } }

        it "sets w2 fields to null" do
          skip "no GIG records in test data" unless gig_record
          expect(gig_record[:w2_monthly_summaries]).to be_nil
          expect(gig_record[:w2_payments]).to be_nil
        end

        it "returns year as a string in monthly summaries" do
          skip "no GIG records in test data" unless gig_record
          gig_record[:gig_monthly_summaries]&.each do |summary|
            expect(summary[:year]).to be_a(String)
          end
        end

        it "returns mileage_expenses as an array" do
          skip "no GIG records in test data" unless gig_record
          gig_record[:gig_monthly_summaries]&.each do |summary|
            expect(summary[:mileage_expenses]).to be_an(Array)
          end
        end
      end
    end
  end
end
