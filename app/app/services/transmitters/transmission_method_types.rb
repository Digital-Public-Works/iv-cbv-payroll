module Transmitters::TransmissionMethodTypes
  METHOD_TYPES = {
    sftp: 0,
    shared_email: 1,
    encrypted_s3: 2,
    json: 3,
    webhook: 4
  }.freeze

  def self.transmitter_class(method_type)
    case method_type.to_s
    when "shared_email"
      Transmitters::SharedEmailTransmitter
    when "sftp"
      Transmitters::SftpTransmitter
    when "encrypted_s3"
      Transmitters::EncryptedS3Transmitter
    when "json"
      Transmitters::JsonTransmitter
    when "webhook"
      Transmitters::WebhookTransmitter
    else
      raise ArgumentError, "Unsupported transmission method: #{method_type}"
    end
  end
end
