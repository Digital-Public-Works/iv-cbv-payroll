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

      begin
        @cbv_flow = CbvFlow.find(@payroll_account.cbv_flow_id)
        NewRelic::Agent.record_custom_event(TrackEvent::ApplicantReportAttemptedUsefulRequirements, {
          time: Time.now.to_i,
          cbv_applicant_id: @cbv_flow&.cbv_applicant_id,
          cbv_flow_id: @payroll_account.cbv_flow_id,
          device_id: @cbv_flow&.device_id,
          invitation_id: @cbv_flow&.cbv_flow_invitation_id
        })
      rescue => e
        log.error "Failed to send New Relic notification: #{e}"
      end

      valid = account_report.valid?(:useful_report)

      unless valid
        @cbv_flow = CbvFlow.find(@payroll_account.cbv_flow_id) if !@cbv_flow.present?

        NewRelic::Agent.record_custom_event(TrackEvent::ApplicantReportFailedUsefulRequirements, {
          time: Time.now.to_i,
          cbv_applicant_id: @cbv_flow&.cbv_applicant_id,
          cbv_flow_id: @payroll_account.cbv_flow_id,
          device_id: @cbv_flow&.device_id,
          invitation_id: @cbv_flow&.cbv_flow_invitation_id,
          errors: account_report.errors.full_messages.join(", ")
        })
      end

      ValidationResult.new(
        account_report: account_report,
        valid: valid,
        errors: account_report.errors
      )
    end
  end
end
