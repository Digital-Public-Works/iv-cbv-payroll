class CbvFlowTransmissionJob < ApplicationJob
  include Cbv::AggregatorDataHelper

  queue_as :report_sender

  def perform(cbv_flow_transmission_id)
    transmission = CbvFlowTransmission.find(cbv_flow_transmission_id)
    return if transmission.succeeded?

    cbv_flow = transmission.cbv_flow
    current_agency = agency_config[cbv_flow.client_agency_id]
    raise "Client agency #{cbv_flow.client_agency_id} not found for CbvFlow #{cbv_flow.id}" unless current_agency

    # TODO: refactor AggregatorDataHelper to accept cbv_flow as a parameter
    # instead of relying on the @cbv_flow instance variable side-effect.
    @cbv_flow = cbv_flow
    aggregator_report = set_aggregator_report

    begin
      transmitter_class(transmission.method_type)
        .new(cbv_flow, current_agency, aggregator_report, transmission.configuration)
        .deliver
    rescue => e
      transmission.update!(status: :failed, last_error: e.message)
      raise
    end

    record_success!(transmission, cbv_flow, aggregator_report)
  end

  def agency_config
    ClientAgencyConfig.instance
  end

  private

  def record_success!(transmission, cbv_flow, aggregator_report)
    now = Time.current
    transmission.update!(status: :succeeded, succeeded_at: now, last_error: nil)

    first_success = false
    cbv_flow.with_lock do
      cbv_flow.reload
      if cbv_flow.transmitted_at.blank?
        cbv_flow.update!(transmitted_at: now)
        first_success = true
      end
    end

    return unless first_success

    track_transmitted_event(cbv_flow, aggregator_report&.paystubs&.count || 0)
    enqueue_agency_name_matching_job(cbv_flow)
  end

  def enqueue_agency_name_matching_job(cbv_flow)
    return unless cbv_flow.cbv_applicant.agency_expected_names.any?

    MatchAgencyNamesJob.perform_later(cbv_flow.id)
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

  def transmitter_class(method_type)
    case method_type.to_s
    when "shared_email"
      Transmitters::SharedEmailTransmitter
    when "sftp"
      Transmitters::SftpTransmitter
    when "encrypted_s3"
      Transmitters::EncryptedS3Transmitter
    when "json"
      Transmitters::JsonTransmitter
    when "webhook"
      Transmitters::WebhookTransmitter
    else
      raise "Unsupported transmission method: #{method_type}"
    end
  end
end
