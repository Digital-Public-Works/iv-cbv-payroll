class Transmitters::EncryptedS3Transmitter < Transmitters::UnencryptedS3Transmitter
  include GpgEncryptable

  protected

  def pre_deliver_check(config)
    if config["public_key"].blank?
      Rails.logger.error("Public key is missing from transmission_method_configuration")
      raise "Public key is required for encrypted S3 transmission"
    end
  end

  def prepare_upload(tempfile, config)
    encrypted = gpg_encrypt_file(tempfile.path, config["public_key"])
    if encrypted.nil?
      Rails.logger.error "Failed to encrypt file: encrypted_tempfile is nil"
      raise "Encryption failed"
    end
    encrypted
  end

  def method_type_for_filename
    :encrypted_s3
  end
end
