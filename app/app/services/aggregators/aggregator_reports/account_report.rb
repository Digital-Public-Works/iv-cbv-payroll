module Aggregators::AggregatorReports
  # Represents the aggregated payroll data for a single employer account.
  # Built by AggregatorReport#find_account_report from raw API responses.
  # Validated via UsefulReportValidator to ensure minimum data requirements are met.
  # Use AccountReportService#validate to call find_account_report and validate in one step.
  AccountReport = Struct.new(:identity, :income, :employment, :paystubs, :gigs, keyword_init: true) do
    include ActiveModel::Validations

    validates_with Aggregators::Validators::UsefulReportValidator, on: :useful_report

    def identities
      identity ? [ identity ] : []
    end

    def incomes
      income ? [ income ] : []
    end

    def employments
      employment ? [ employment ] : []
    end
  end
end
