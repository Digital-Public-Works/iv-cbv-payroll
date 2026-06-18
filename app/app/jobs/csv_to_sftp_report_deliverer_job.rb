class CsvToSftpReportDelivererJob < ApplicationJob
  def perform(partner_id, date_start, date_end)
    agency = ClientAgencyConfig.instance[partner_id]

    unless agency.has_transmission_method?("sftp")
      Rails.logger.error "#{partner_id} has no sftp transmission method configured, skipping CSV summary delivery"
      return
    end

    config = agency.transmission_configuration_for("sftp")

    cbv_flows = CbvFlow.where(transmitted_at: date_start..date_end, client_agency_id: partner_id).includes(:cbv_applicant, :cbv_flow_invitation)

    if cbv_flows.empty?
      Rails.logger.info "delivered 0 applications for #{partner_id} in time range #{date_start}..#{date_end}"
      return
    end

    csv = RecentlySubmittedCasesCsv.new(agency).generate_csv(cbv_flows)

    # TODO: Make this not sftp-specific. Verify functionality.
    sftp_gateway = sftp_gateway(config)
    sftp_gateway.upload_data(csv, "#{config["path_prefix"]}/#{filename(agency, date_start)}")

    Rails.logger.info "delivered #{cbv_flows.count} applications for #{partner_id} in time range #{date_start}..#{date_end}"
  end

  def sftp_gateway(config)
    SftpGateway.new(config)
  end

  def filename(agency, date_start)
    "#{date_start.in_time_zone(agency.timezone).strftime('%Y%m%d')}_summary.csv"
  end
end
