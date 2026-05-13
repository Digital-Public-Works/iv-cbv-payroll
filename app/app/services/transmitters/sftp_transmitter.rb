class Transmitters::SftpTransmitter
  include Transmitter

  def deliver
    sftp_gateway = SftpGateway.new(@transmission_config)
    filename = current_agency.pdf_filename(cbv_flow, cbv_flow.consented_to_authorized_use_at)
    sftp_gateway.upload_data(StringIO.new(pdf_output.content), "#{@transmission_config["sftp_directory"]}/#{filename}.pdf")
  end

  def pdf_output
    @_pdf_output ||= begin
      pdf_service = PdfService.new(language: :en)
      pdf_service.generate(cbv_flow, aggregator_report, current_agency)
    end
  end
end
