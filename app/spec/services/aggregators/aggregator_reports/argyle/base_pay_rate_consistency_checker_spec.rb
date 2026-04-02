require 'rails_helper'

RSpec.describe Aggregators::AggregatorReports::Argyle::BasePayRateConsistencyChecker, type: :service do
  describe "#match?" do
    let(:income) {
      Aggregators::ResponseObjects::Income.new(
        compensation_amount: income_base_amount,
        compensation_unit: income_base_unit
      ) }
    let(:paystubs) { [ paystub1, paystub2 ] }
    let(:paystub1) { Aggregators::ResponseObjects::Paystub.new(
        implied_base_rate_in_dollars: paystub1_base) }
    let(:paystub2) { Aggregators::ResponseObjects::Paystub.new(
        implied_base_rate_in_dollars: paystub2_base) }
    let(:income_base_amount) { 2000 } # This is in cents
    let(:income_base_unit) { "hourly" }
    let(:paystub1_base) { "20.0000" }
    let(:paystub2_base) { "20.0000" }

    subject(:checker) { described_class.new(income: income, paystubs: paystubs).match? }

    context "when the employment level base rates and all paystub base rates match exactly" do
      it { is_expected.to be true }
    end

    context "when the employment level base rates and all paystub base rates within 1 cent" do
      let(:paystub1_base) { "20.0090" }

      it { is_expected.to be true }
    end

    context "when the employment level base rate and one paystub rate matches and all others are nil" do
      let(:paystub2_base) { nil }

      it { is_expected.to be true }
    end

    context "when there are no values for the paystub rates" do
      let(:paystub1_base) { nil }
      let(:paystub2_base) { nil }

      it { is_expected.to be true }
    end

    context "when the employment base compensation is not hourly" do
      let(:income_base_amount) { 9990 }
      let(:income_base_unit) { "annually" }

      it { is_expected.to be true }
    end

    context "when the paystubs are inconsistent with each other by at least one cent" do
      let(:paystub1_base) { "20.0100" }

      it { is_expected.to be false }
    end

    context "when the paystubs match but the employment level compensation amount is different by at least one cent" do
      let(:income_base_amount) { 2001 }

      it { is_expected.to be false }
    end
  end
end
