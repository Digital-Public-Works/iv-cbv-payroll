module Aggregators
  class ReportValidationService
    # Result object returned by validate_account
    class Result
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

    # Validates the account report for a specific payroll account
    # Returns a Result object with the account_report, validity status, and errors
    def validate
      account_id = @payroll_account.aggregator_account_id
      account_report = @report.find_account_report(account_id)
      valid = account_report.valid?(:useful_report)

      Result.new(
        account_report: account_report,
        valid: valid,
        errors: account_report.errors
      )
    end
  end
end
