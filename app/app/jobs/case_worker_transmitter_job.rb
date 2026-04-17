class CaseWorkerTransmitterJob < ApplicationJob
  queue_as :report_sender

  def perform(cbv_flow_id)
    cbv_flow = CbvFlow.find(cbv_flow_id)
    current_agency = current_agency(cbv_flow)
    raise "Client agency #{cbv_flow.client_agency_id} not found for CbvFlow #{cbv_flow.id}" unless current_agency

    transmissions = synchronize_transmissions!(cbv_flow, current_agency)

    transmissions.each do |transmission|
      next if transmission.succeeded?

      enqueue_transmission_job(transmission.id)
    end
  end

  private

  def synchronize_transmissions!(cbv_flow, current_agency)
    configured_methods = current_agency.transmission_methods.index_by { |entry| entry.method.to_s }

    cbv_flow.cbv_flow_transmissions.where.not(method_type: configured_methods.keys).destroy_all

    configured_methods.map do |method_type, entry|
      validate_method_type!(method_type)

      transmission = cbv_flow.cbv_flow_transmissions.find_or_initialize_by(method_type: method_type)
      transmission.configuration = entry.configuration
      transmission.status = :pending if transmission.failed?
      transmission.save! if transmission.new_record? || transmission.changed?
      transmission
    end
  end

  def enqueue_transmission_job(transmission_id)
    if test_queue_adapter?
      begin
        CbvFlowTransmissionJob.perform_now(transmission_id)
      rescue StandardError
        # In test mode perform_now raises synchronously. The job has already persisted the
        # error on the transmission row, so swallow so sibling methods still fire.
      end
    else
      CbvFlowTransmissionJob.perform_later(transmission_id)
    end
  end

  def current_agency(cbv_flow)
    ClientAgencyConfig.instance[cbv_flow.client_agency_id]
  end

  def validate_method_type!(method_type)
    return if CbvFlowTransmission.method_types.key?(method_type.to_s)

    raise "Unsupported transmission method: #{method_type}"
  end
end
