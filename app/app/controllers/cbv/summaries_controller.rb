class Cbv::SummariesController < Cbv::BaseController
  include Cbv::AggregatorDataHelper

  before_action :ensure_applicant_information_completed, only: %i[show]
  before_action :set_aggregator_report, only: %i[show]
  before_action :check_aggregator_report, only: %i[show]

  def show
    track_accessed_income_summary_event(@cbv_flow)
  end

  private

  # can't show summary if there is still applicant info to collect. applicant shouldn't get here without required
  # info entered anyway, this is a guard
  def ensure_applicant_information_completed
    return if @cbv_flow.applicant_information_completed?

    redirect_to cbv_flow_applicant_information_path
  end

  def check_aggregator_report
    if @aggregator_report.nil?
      Rails.logger.error "Aggregator report nil for #{@cbv_flow.id}. User reached summary page without successfully synced payroll accounts."
      redirect_to cbv_flow_synchronization_failures_path
    end
  end

  def track_accessed_income_summary_event(cbv_flow)
    event_logger.track(TrackEvent::ApplicantAccessedIncomeSummary, request, {
      time: Time.now.to_i,
      client_agency_id: current_agency&.id,
      cbv_flow_id: cbv_flow.id,
      cbv_applicant_id: cbv_flow.cbv_applicant_id,
      device_id: cbv_flow.device_id,
      invitation_id: cbv_flow.cbv_flow_invitation_id,
      account_count: cbv_flow.payroll_accounts.count,
      paystub_count: @aggregator_report.paystubs.count,
      account_count_with_additional_information:
        cbv_flow.additional_information.values.count { |info| info["comment"].present? },
      flow_started_seconds_ago: (Time.now - cbv_flow.created_at).to_i,
      language: I18n.locale
    })
  end
end
