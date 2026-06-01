require "rails_helper"

RSpec.describe ReportFilename do
  let(:cbv_applicant) { create(:cbv_applicant, case_number: "STEM01") }
  let(:cbv_flow) do
    create(:cbv_flow,
      :invited,
      :with_pinwheel_account,
      cbv_applicant: cbv_applicant,
      confirmation_code: "STEMCONF"
    )
  end
  let(:aggregator_report) do
    instance_double(
      Aggregators::AggregatorReports::AggregatorReport,
      from_date: Date.new(2025, 1, 15),
      to_date: Date.new(2025, 4, 30)
    )
  end

  describe ".stem" do
    it "matches the canonical IncomeReport_<id>_<MonStart>-<MonEnd><Year>_Conf<code>_<ts> format" do
      stem = described_class.stem(cbv_flow, aggregator_report, at: Time.utc(2025, 5, 12, 15, 5, 6))
      expect(stem).to eq("IncomeReport_STEM01_Jan-Apr2025_ConfSTEMCONF_20250512150506")
    end
  end

  describe ".paystubs_filename" do
    it "appends _paystubs.pdf to the stem" do
      expect(described_class.paystubs_filename("IncomeReport_X")).to eq("IncomeReport_X_paystubs.pdf")
    end
  end

  describe ".report_filename" do
    it "appends .pdf to the stem" do
      expect(described_class.report_filename("IncomeReport_X")).to eq("IncomeReport_X.pdf")
    end
  end
end
