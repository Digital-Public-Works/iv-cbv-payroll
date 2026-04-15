class CbvFlowTransmissionFinalizeJob < ApplicationJob
  include Cbv::AggregatorDataHelper

  queue_as :report_sender

  def perform(cbv_flow_transmission_id)
    transmission = CbvFlowTransmission.includes(:cbv_flow, :cbv_flow_transmission_attempts).find(cbv_flow_transmission_id)
    cbv_flow = transmission.cbv_flow
    should_track_and_enqueue_follow_up = false

    transmission.with_lock do
      transmission.reload
      cbv_flow = transmission.cbv_flow.reload
      attempts = transmission.cbv_flow_transmission_attempts.to_a
      return if attempts.empty?
      return unless attempts.all?(&:succeeded?)

      if cbv_flow.transmitted_at.blank?
        cbv_flow.touch(:transmitted_at)
        should_track_and_enqueue_follow_up = true
      end

      transmission.update!(status: :completed, completed_at: cbv_flow.transmitted_at || Time.current)
    end

    return unless should_track_and_enqueue_follow_up

    track_transmitted_event(cbv_flow, paystub_count_for(cbv_flow))
    enqueue_agency_name_matching_job(cbv_flow)
  end

  def agency_config
    ClientAgencyConfig.instance
  end

  private

  def enqueue_agency_name_matching_job(cbv_flow)
    return unless cbv_flow.cbv_applicant.agency_expected_names.any?

    MatchAgencyNamesJob.perform_later(cbv_flow.id)
  end

  def paystub_count_for(cbv_flow)
    # TODO: refactor AggregatorDataHelper to accept cbv_flow as a parameter
    @cbv_flow = cbv_flow
    set_aggregator_report
    @aggregator_report&.paystubs&.count || 0
  rescue => e
    Rails.logger.error("Failed to compute paystub_count for CbvFlow #{cbv_flow.id}: #{e.message}")
    0
  end

  def track_transmitted_event(cbv_flow, paystub_count)
    event_logger.track(TrackEvent::ApplicantSharedIncomeSummary, nil, {
      time: Time.current.to_i,
      client_agency_id: cbv_flow.client_agency_id,
      cbv_applicant_id: cbv_flow.cbv_applicant_id,
      cbv_flow_id: cbv_flow.id,
      device_id: cbv_flow.device_id,
      invitation_id: cbv_flow.cbv_flow_invitation_id,
      account_count: cbv_flow.fully_synced_payroll_accounts.count,
      time_since_invite_seconds: cbv_flow.cbv_flow_invitation&.created_at &&
        Time.current - cbv_flow.cbv_flow_invitation.created_at,
      paystub_count: paystub_count,
      account_count_with_additional_information:
        cbv_flow.additional_information.values.count { |info| info["comment"].present? },
      flow_started_seconds_ago: (cbv_flow.consented_to_authorized_use_at - cbv_flow.created_at).to_i,
      locale: I18n.locale
    })
  end
end
