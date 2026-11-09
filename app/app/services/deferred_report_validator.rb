# run the usefulReportValidator for reports that needed to have applicant data collected
class DeferredReportValidator
  include Cbv::AggregatorDataHelper

  Result = Struct.new(:valid_accounts, :invalid_accounts, keyword_init: true) do
    def any_valid?
      valid_accounts.any?
    end

    def first_invalid_account
      invalid_accounts.first
    end
  end

  def initialize(cbv_flow, event_logger: nil, request: nil)
    @cbv_flow = cbv_flow
    @event_logger = event_logger
    @request = request
  end

  def run
    valid_accounts = []
    invalid_accounts = []

    @cbv_flow.payroll_accounts_awaiting_validation.each do |payroll_account|
      if validate(payroll_account)
        payroll_account.update(report_status: :useful)
        valid_accounts << payroll_account
      else
        payroll_account.update(report_status: :not_useful)
        invalid_accounts << payroll_account
      end
    end

    Result.new(valid_accounts: valid_accounts, invalid_accounts: invalid_accounts)
  end

  private

  def validate(payroll_account)
    return false unless payroll_account.sync_succeeded?

    set_aggregator_report_for_account(payroll_account)
    result = Aggregators::AccountReportService.new(@aggregator_report, payroll_account).validate

    track_validation_result(payroll_account, result)

    result.valid?
  rescue StandardError => e
    # A report we cannot even build is not a useful report. Fail the account
    # rather than leaving it undecided, which would strand the applicant.
    Rails.logger.error("Deferred validation failed for payroll account #{payroll_account.id}: #{e.message}")
    NewRelic::Agent.notice_error(e)
    false
  end

  def track_validation_result(payroll_account, result)
    return if @event_logger.nil?

    event = result.valid? ? TrackEvent::ApplicantReportMetUsefulRequirements : TrackEvent::ApplicantReportFailedUsefulRequirements
    properties = {
      time: Time.now.to_i,
      cbv_applicant_id: @cbv_flow.cbv_applicant_id,
      cbv_flow_id: @cbv_flow.id,
      device_id: @cbv_flow.device_id,
      invitation_id: @cbv_flow.cbv_flow_invitation_id,
      aggregator_account_id: payroll_account.id,
      deferred: true
    }
    properties[:errors] = result.error_messages unless result.valid?

    @event_logger.track(event, @request, properties)
  end

  # Cbv::AggregatorDataHelper reaches for these the way a controller provides them.
  def agency_config
    ClientAgencyConfig.instance
  end
end
