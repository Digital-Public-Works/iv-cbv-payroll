module Transmitters::TransmissionMethodTypes
  # Stored as integers on partner_transmission_methods and cbv_flow_transmissions.
  # 2 (encrypted_s3) and 5 (unencrypted_s3) are retired: both became s3 (6).
  # Do not re-use 2 or 5 as it may cause conflicts
  METHOD_TYPES = {
    sftp: 0,
    shared_email: 1,
    json: 3,
    webhook: 4,
    s3: 6
  }.freeze

  def self.transmitter_class(method_type)
    case method_type.to_s
    when "shared_email"
      Transmitters::SharedEmailTransmitter
    when "sftp"
      Transmitters::SftpTransmitter
    when "s3"
      Transmitters::S3Transmitter
    when "json"
      Transmitters::JsonTransmitter
    when "webhook"
      Transmitters::WebhookTransmitter
    else
      raise ArgumentError, "Unsupported transmission method: #{method_type}"
    end
  end
end
