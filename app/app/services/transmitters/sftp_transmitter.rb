class Transmitters::SftpTransmitter
  include Transmitter
  include Transmitters::Concerns::PaystubsOutput

  def deliver
    sftp_gateway = SftpGateway.new(@transmission_config)
    path = TransmissionFilename.full_path(
      cbv_flow: cbv_flow,
      agency: current_agency,
      method_type: :sftp,
      remote_directory: @transmission_config["path_prefix"]
    )
    sftp_gateway.upload_data(StringIO.new(pdf_output.content), path)

    if (paystubs = paystubs_output)
      paystubs_path = TransmissionFilename.full_path(
        cbv_flow: cbv_flow,
        agency: current_agency,
        method_type: :sftp,
        remote_directory: @transmission_config["path_prefix"],
        suffix: "_paystubs"
      )
      sftp_gateway.upload_data(StringIO.new(paystubs.content), paystubs_path)
    end
  end

  def pdf_output
    @_pdf_output ||= begin
      pdf_service = PdfService.new(language: :en)
      pdf_service.generate(cbv_flow, aggregator_report, current_agency)
    end
  end
end
