class Transmitters::SftpTransmitter
  include Transmitter

  def deliver
    sftp_gateway = SftpGateway.new(@transmission_config)
    filename = TransmissionFilename.for(cbv_flow, current_agency, :sftp)
    sftp_gateway.upload_data(StringIO.new(pdf_output.content), "#{@transmission_config["sftp_directory"]}/#{filename}")
  end

  def pdf_output
    @_pdf_output ||= begin
      pdf_service = PdfService.new(language: :en)
      pdf_service.generate(cbv_flow, aggregator_report, current_agency)
    end
  end
end
