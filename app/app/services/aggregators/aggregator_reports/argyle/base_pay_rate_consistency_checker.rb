module Aggregators::AggregatorReports
  module Argyle
    class BasePayRateConsistencyChecker
      def initialize(income: nil, paystubs: nil)
        @income = income
        @paystubs = paystubs
      end

      def match?
        # Consider values compatible if they are in different units or there is nothing to compare
        return true unless @income&.compensation_amount.present?
        return true unless @income&.compensation_unit == "hourly"
        return true if paystubs_base_rates.none?

        return true if paystubs_match && employment_match

        false
      end

      private
      def paystubs_base_rates
        @paystubs_base_rates ||= @paystubs&.map(&:implied_base_rate_in_dollars)
      end

      def paystubs_base_rates_unique
        @paystubs_base_rates_unique ||= paystubs_base_rates.compact.map { |rate| rate.to_d * 100 }
      end

      def paystubs_match
        return true if paystubs_base_rates.count == 1

        within_one_cent(paystubs_base_rates_unique.max, paystubs_base_rates_unique.min)
      end

      def employment_match
        employment_base_rate = @income.compensation_amount.to_d

        paystubs_base_rates_unique.all? do |paystub_rate|
          within_one_cent(employment_base_rate, paystub_rate)
        end
      end

      def within_one_cent(rate_1, rate_2)
        (rate_1 - rate_2).abs < 1
      end
    end
  end
end
