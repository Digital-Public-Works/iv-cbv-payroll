# Per-method transmission worker. CaseWorkerTransmitterJob orchestrates which
# methods need to run for a given CbvFlow and enqueues one of these jobs per
# method (sftp, webhook, shared_email, etc.); this job delivers a single method
# and records the outcome on its CbvFlowTransmission row. Shoryuken handles
# retries on failure.
class CbvFlowTransmissionJob < ApplicationJob
  include Cbv::AggregatorDataHelper

  queue_as :report_sender

  def perform(cbv_flow_transmission_id)
    transmission = CbvFlowTransmission.find_by(id: cbv_flow_transmission_id)
    raise "CbvFlowTransmission #{cbv_flow_transmission_id} not found" unless transmission
    return if transmission.succeeded?

    cbv_flow = transmission.cbv_flow
    current_agency = agency_config[cbv_flow.client_agency_id]
    raise "Client agency #{cbv_flow.client_agency_id} not found for CbvFlow #{cbv_flow.id}" unless current_agency

    # TODO: refactor AggregatorDataHelper to accept cbv_flow as a parameter
    # instead of relying on the @cbv_flow instance variable side-effect.
    @cbv_flow = cbv_flow
    aggregator_report = set_aggregator_report

    # Shoryuken retries on any raised error. If the external delivery actually
    # landed but the job failed after (e.g. connection reset on the upload
    # response, or the transmission.update! below raises), the retry will
    # re-run deliver. Transmitters dedupe via confirmation_code embedded in
    # the payload/filename so receivers can collapse duplicates. Two caveats
    # where dedup breaks: encrypted_s3 filenames include a per-attempt
    # timestamp (every retry is a new S3 object), and sftp pdf_filename uses
    # a date rather than a timestamp (same-day retries overwrite, cross-
    # midnight retries land as a second file).
    begin
      Transmitters::TransmissionMethodTypes.transmitter_class(transmission.method_type)
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

  # record_success! includes the business logic on how to handle the first and subsequent
  # successful transmission to a partner. (e.g. a report may get sent over shared email
  # before it transmits over sftp)
  def record_success!(transmission, cbv_flow, aggregator_report)
    now = Time.current
    first_success = false

    # update the corresponding db fields as a transaction.
    ActiveRecord::Base.transaction do
      transmission.update!(status: :succeeded, succeeded_at: now, last_error: nil)
      first_success = first_transmission_success?(cbv_flow, now)
    end

    # for each successful transmission, send an analytics event
    track_transmitted_event(cbv_flow, transmission, aggregator_report&.paystubs&.count || 0)

    return unless first_success

    # only for the first successful transmission, enqueue the agency name matching job
    enqueue_agency_name_matching_job(cbv_flow)
  end

  # Stamps cbv_flow.transmitted_at on the first successful delivery. Later
  # successes return false without overwriting.
  def first_transmission_success?(cbv_flow, now)
    return false if cbv_flow.transmitted_at.present?

    cbv_flow.with_lock do
      return false if cbv_flow.reload.transmitted_at.present?
      cbv_flow.update!(transmitted_at: now)
    end
    true
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
end
