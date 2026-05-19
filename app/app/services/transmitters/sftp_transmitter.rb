class Transmitters::SftpTransmitter
  include Transmitter

  def deliver
    sftp_gateway = SftpGateway.new(@transmission_config)
    path = TransmissionFilename.full_path(cbv_flow, current_agency, :sftp, @transmission_config["sftp_directory"])
    sftp_gateway.upload_data(StringIO.new(pdf_output.content), path)
  end

  def pdf_output
    @_pdf_output ||= begin
      pdf_service = PdfService.new(language: :en)
      pdf_service.generate(cbv_flow, aggregator_report, current_agency)
    end
  end
end
