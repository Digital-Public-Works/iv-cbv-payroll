# Sends a TransmissionComplete webhook event after one non-webhook transmission
# method (sftp, encrypted_s3, shared_email, etc.) has delivered successfully for
# a CbvFlow. CbvFlowTransmissionJob enqueues one of these per successful method,
# only when the flow also has a webhook transmission on the events contract
# (contract_version "2"; legacy webhook consumers only accept ReportSubmission).
class TransmissionCompleteWebhookJob < ApplicationJob
  queue_as { self.class.queue_with_suffix(:report_sender) }

  def perform(cbv_flow_transmission_id)
    transmission = CbvFlowTransmission.find_by(id: cbv_flow_transmission_id)
    raise "CbvFlowTransmission #{cbv_flow_transmission_id} not found" unless transmission
    raise "CbvFlowTransmission #{transmission.id} has not succeeded" unless transmission.succeeded?
    return if transmission.webhook?

    cbv_flow = transmission.cbv_flow
    webhook_transmission = cbv_flow.cbv_flow_transmissions.webhook.first
    return unless webhook_transmission

    webhook_client = Transmitters::WebhookClient.new(webhook_transmission.configuration)
    return unless webhook_client.events_contract?

    current_agency = agency_config[cbv_flow.client_agency_id]
    raise "Client agency #{cbv_flow.client_agency_id} not found for CbvFlow #{cbv_flow.id}" unless current_agency

    webhook_client.post_event(
      event_type: Transmitters::WebhookClient::TRANSMISSION_COMPLETE,
      confirmation_code: cbv_flow.confirmation_code,
      payload: {
        confirmation_code: cbv_flow.confirmation_code,
        transmission_method: transmission.method_type,
        uri: asset_uri(transmission, cbv_flow, current_agency),
        completed_at: transmission.succeeded_at.utc.iso8601
      }
    )
  end

  def agency_config
    ClientAgencyConfig.instance
  end

  private

  def asset_uri(transmission, cbv_flow, current_agency)
    method_type = transmission.method_type.to_sym
    return nil unless TransmissionFilename::EXTENSIONS.key?(method_type)

    TransmissionFilename.full_path(
      cbv_flow: cbv_flow,
      agency: current_agency,
      method_type: method_type,
      remote_directory: TransmissionFilename.remote_directory_from_config(
        method_type: method_type,
        configuration: transmission.configuration
      )
    )
  end
end
