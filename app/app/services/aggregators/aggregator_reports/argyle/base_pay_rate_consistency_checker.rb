module Aggregators::AggregatorReports
  module Argyle
    class BasePayRateConsistencyChecker
      def initialize(incomes: nil, paystubs: nil)
        @incomes = incomes
        @paystubs = paystubs
      end

      def match?
        # Consider values compatible if they are in different units or there is nothing to compare
        return true unless income.compensation_amount.present?
        return true unless income.compensation_unit == "hourly"
        return true if paystubs_base_rates.none?

        return false if paystubs_mismatch || employment_mismatch

        true
      end

      private
      def income
        @income ||= @incomes.first
      end

      def paystubs_base_rates
        @paystubs_base_rates ||= @paystubs.map(&:implied_base_rate_in_dollars)
      end

      def paystubs_mismatch
        return false if paystubs_base_rates.count == 1

        paystubs_base_rates_decimal = paystubs_base_rates.compact.map(&:to_d)

        (paystubs_base_rates_decimal.max - paystubs_base_rates_decimal.min).abs >= 0.01
      end

      def employment_mismatch
        paystubs_base_rates_decimal = paystubs_base_rates.compact.map(&:to_d)
        employment_base_rate_decimal = income.compensation_amount.to_d

        paystubs_base_rates_decimal.any? do |paystub_rate_in_dollars|
          (employment_base_rate_decimal - (paystub_rate_in_dollars*100)).abs >= 1
        end
      end
    end
  end
end
