class CbvFlowTransmissionAttemptJob < ApplicationJob
  include Cbv::AggregatorDataHelper

  queue_as :report_sender

  def perform(cbv_flow_transmission_attempt_id)
    attempt = CbvFlowTransmissionAttempt.find(cbv_flow_transmission_attempt_id)
    if attempt.succeeded?
      enqueue_finalize_job(attempt.cbv_flow_transmission_id)
      return
    end

    cbv_flow = attempt.cbv_flow_transmission.cbv_flow
    current_agency = agency_config[cbv_flow.client_agency_id]
    raise "Client agency #{cbv_flow.client_agency_id} not found for CbvFlow #{cbv_flow.id}" unless current_agency

    return unless mark_processing!(attempt)

    begin
      # TODO: refactor AggregatorDataHelper to accept cbv_flow as a parameter
      # instead of relying on the @cbv_flow instance variable side-effect.
      @cbv_flow = cbv_flow
      aggregator_report = set_aggregator_report
      transmitter_class(attempt.method_type)
        .new(cbv_flow, current_agency, aggregator_report, attempt.configuration)
        .deliver
    rescue => e
      attempt.update!(status: :failed, last_error: e.message)
      attempt.cbv_flow_transmission.update!(status: :failed, completed_at: nil)
      raise
    end

    attempt.update!(status: :succeeded, succeeded_at: Time.current, last_error: nil)
    enqueue_finalize_job(attempt.cbv_flow_transmission_id)
  end

  def agency_config
    ClientAgencyConfig.instance
  end

  private

  def mark_processing!(attempt)
    attempt.with_lock do
      attempt.reload
      return false if attempt.succeeded?

      attempt.update!(
        status: :processing,
        attempt_count: attempt.attempt_count + 1,
        last_attempted_at: Time.current,
        last_error: nil
      )
      true
    end
  end

  def enqueue_finalize_job(cbv_flow_transmission_id)
    if test_queue_adapter?
      CbvFlowTransmissionFinalizeJob.perform_now(cbv_flow_transmission_id)
    else
      CbvFlowTransmissionFinalizeJob.perform_later(cbv_flow_transmission_id)
    end
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
