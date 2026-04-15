class CaseWorkerTransmitterJob < ApplicationJob
  queue_as :report_sender

  def perform(cbv_flow_id)
    cbv_flow = CbvFlow.find(cbv_flow_id)
    current_agency = current_agency(cbv_flow)
    raise "Client agency #{cbv_flow.client_agency_id} not found for CbvFlow #{cbv_flow.id}" unless current_agency

    transmission = CbvFlowTransmission.find_or_create_by!(cbv_flow: cbv_flow)
    synchronize_attempts!(transmission, current_agency)

    attempts = transmission.cbv_flow_transmission_attempts.where.not(status: :succeeded)
    return if attempts.empty?

    transmission.update!(status: :pending, completed_at: nil)
    attempts.find_each do |attempt|
      enqueue_attempt_job(attempt.id)
    end
  end

  private

  def synchronize_attempts!(transmission, current_agency)
    configured_methods = current_agency.transmission_methods.index_by { |entry| entry.method.to_s }

    transmission.cbv_flow_transmission_attempts.where.not(method_type: configured_methods.keys).destroy_all

    configured_methods.each do |method_type, entry|
      validate_method_type!(method_type)

      attempt = transmission.cbv_flow_transmission_attempts.find_or_initialize_by(method_type: method_type)
      attempt.configuration = entry.configuration
      attempt.status = :pending if attempt.failed?
      attempt.save! if attempt.new_record? || attempt.changed?
    end
  end

  def enqueue_attempt_job(attempt_id)
    if test_queue_adapter?
      CbvFlowTransmissionAttemptJob.perform_now(attempt_id)
    else
      CbvFlowTransmissionAttemptJob.perform_later(attempt_id)
    end
  end

  def current_agency(cbv_flow)
    ClientAgencyConfig.instance[cbv_flow.client_agency_id]
  end

  def validate_method_type!(method_type)
    return if CbvFlowTransmissionAttempt.method_types.key?(method_type.to_s)

    raise "Unsupported transmission method: #{method_type}"
  end
end
