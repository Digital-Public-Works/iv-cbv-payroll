class Transmitters::UnencryptedS3Transmitter
  include Transmitter
  include TarFileCreatable
  include CsvHelper

  def deliver
    config = @transmission_config
    pre_deliver_check(config)

    @file_stem = TransmissionFilename.stem(@cbv_flow, @current_agency)

    csv_content = generate_csv

    file_data = [
      { name: "#{@file_stem}.pdf", content: pdf_output&.content },
      { name: "#{@file_stem}.csv", content: csv_content.string }
    ]
    tar_tempfile = create_tar_file(file_data)

    upload_tempfile = nil
    begin
      gzipped_tempfile = gzip_file(tar_tempfile)
      upload_tempfile = prepare_upload(gzipped_tempfile, config)

      S3Service.new(config).upload_file(upload_tempfile.path, upload_key)
    rescue => ex
      Rails.logger.error "Failed to transmit to caseworker: #{ex.message}"
      raise
    ensure
      upload_tempfile.close! if upload_tempfile
    end
  end

  def pdf_output
    @_pdf_output ||= begin
      pdf_service = PdfService.new(language: :en)
      pdf_service.generate(@cbv_flow, @aggregator_report, @current_agency)
    end
  end

  def generate_csv
    payroll_account = PayrollAccount.find_by(cbv_flow_id: @cbv_flow.id)
    applicant = @cbv_flow.cbv_applicant
    identifier_name = @current_agency.partner_identifier_name.to_s

    data = { identifier_name.to_sym => applicant.partner_identifier }

    @current_agency.applicant_attributes.each do |name, _attr|
      next if name.to_s == identifier_name
      data[name.to_sym] = applicant.send(name)
    end

    data.merge!(
      client_email_address: @cbv_flow.cbv_flow_invitation&.email_address,
      report_date_created: payroll_account&.created_at&.strftime("%m/%d/%Y"),
      confirmation_code: @cbv_flow.confirmation_code,
      consent_timestamp: @cbv_flow.consented_to_authorized_use_at&.strftime("%m/%d/%Y %H:%M:%S"),
      pdf_filename: "#{@file_stem}.pdf",
      pdf_filetype: "application/pdf",
      pdf_filesize: pdf_output.file_size,
      pdf_number_of_pages: pdf_output.page_count
    )

    create_csv(data)
  end

  def gzip_file(input_tempfile)
    gzipped_tempfile = Tempfile.new(%w[gzipped .gz])
    gzipped_tempfile.binmode
    gzipped_path = gzipped_tempfile.path
    raise "Failed to gzip file" if gzipped_path.nil?

    Zlib::GzipWriter.open(gzipped_path) do |gz|
      input_tempfile.binmode
      input_tempfile.rewind
      gz.write(input_tempfile.read)
    end

    gzipped_tempfile.rewind
    gzipped_tempfile
  ensure
    input_tempfile.close unless input_tempfile.closed?
  end

  protected

  # no-op by default, encrypted_s3 verifies there is a public key
  def pre_deliver_check(_config); end

  # by default a no-op; subclass can transform (encrypted_s3 encrypts here)
  def prepare_upload(tempfile, _config); tempfile; end

  # this is defined as an instance method to allow encrypted_s3_transmitter subclass to override
  def upload_key
    TransmissionFilename.for(@cbv_flow, @current_agency, :unencrypted_s3)
  end
end
