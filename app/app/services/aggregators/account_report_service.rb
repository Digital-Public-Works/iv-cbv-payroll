module Aggregators
  class AccountReportService
    class ValidationResult
      attr_reader :account_report, :errors

      def initialize(account_report:, valid:, errors:)
        @account_report = account_report
        @valid = valid
        @errors = errors
      end

      def valid?
        @valid
      end

      def error_messages
        errors.full_messages.join(", ")
      end
    end

    def initialize(report, payroll_account)
      @report = report
      @payroll_account = payroll_account
    end

    def validate
      account_report = @report.find_account_report(@payroll_account.aggregator_account_id)
      valid = account_report.valid?(:useful_report)

      ValidationResult.new(
        account_report: account_report,
        valid: valid,
        errors: account_report.errors
      )
    end
  end
end
