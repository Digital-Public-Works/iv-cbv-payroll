class RecentlySubmittedCasesCsv < CsvGenerator
  def initialize(agency)
    @agency = agency
  end

  def generate_csv(cbv_flows)
    # dynamic expiration header based on configured partner identifier
    identifier_header = (@agency.partner_identifier_name || "partner_identifier").to_sym

    data = cbv_flows.map do |cbv_flow|
      invitation = cbv_flow.cbv_flow_invitation

      {
        identifier_header => cbv_flow.cbv_applicant.partner_identifier,
        confirmation_code: cbv_flow.confirmation_code,
        cbv_link_created_timestamp: invitation ? @agency.format_timestamp(cbv_flow.cbv_flow_invitation.created_at) : nil,
        cbv_link_clicked_timestamp: @agency.format_timestamp(cbv_flow.created_at),
        report_created_timestamp: @agency.format_timestamp(cbv_flow.consented_to_authorized_use_at),
        consent_timestamp: @agency.format_timestamp(cbv_flow.consented_to_authorized_use_at),
        pdf_filename: TransmissionFilename.for(cbv_flow, @agency, :sftp),
        pdf_filetype: "application/pdf",
        language: invitation&.language
      }
    end

    CsvGenerator.create_csv_multiple_datapoints(data)
  end
end
