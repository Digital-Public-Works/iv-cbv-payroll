# Per-method transmission worker. CaseWorkerTransmitterJob orchestrates which
# methods need to run for a given CbvFlow and enqueues one of these jobs per
# method (sftp, webhook, shared_email, etc.); this job delivers a single method
# and records the outcome on its CbvFlowTransmission row. Shoryuken handles
# retries on failure.
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

    return unless record_first_transmission_success!(cbv_flow, now)

    track_transmitted_event(cbv_flow, transmission, aggregator_report&.paystubs&.count || 0)
    enqueue_agency_name_matching_job(cbv_flow)
  end

  # Stamp cbv_flow.transmitted_at with the timestamp of the first successful
  # per-method delivery. Later successes do NOT overwrite it — transmitted_at
  # represents "when this applicant's data first reached the agency" and is
  # what the weekly summary reports read. Returns true iff this call performed
  # the stamp (so callers can gate one-time side-effects like event tracking).
  def record_first_transmission_success!(cbv_flow, now)
    first = false
    cbv_flow.with_lock do
      cbv_flow.reload
      if cbv_flow.transmitted_at.blank?
        cbv_flow.update!(transmitted_at: now)
        first = true
      end
    end
    first
  end

  def enqueue_agency_name_matching_job(cbv_flow)
    return unless cbv_flow.cbv_applicant.agency_expected_names.any?

    MatchAgencyNamesJob.perform_later(cbv_flow.id)
  end

  def track_transmitted_event(cbv_flow, transmission, paystub_count)
    event_logger.track(TrackEvent::ApplicantSharedIncomeSummary, nil, {
      time: Time.current.to_i,
      client_agency_id: cbv_flow.client_agency_id,
      cbv_applicant_id: cbv_flow.cbv_applicant_id,
      cbv_flow_id: cbv_flow.id,
      cbv_flow_transmission_id: transmission.id,
      transmission_method: transmission.method_type,
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
