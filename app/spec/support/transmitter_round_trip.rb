require "csv"
require "zlib"
require "rubygems/package"
require "pdf-reader"

# Helpers for asserting that an S3-transmitted artifact actually contains
# what the transmitter says it does — not just that *something* landed.
module TransmitterRoundTrip
  # Downloads `key` from `bucket` via `s3_client` and returns the body as
  # a binary string.
  def download_object(s3_client, bucket, key)
    s3_client.get_object(bucket: bucket, key: key).body.read
  end

  # Decrypts a GPG-encrypted byte string using whichever private key is
  # already imported into the active GNUPGHOME. Returns the plaintext bytes.
  def gpg_decrypt(encrypted_bytes)
    output = StringIO.new(+"".b)
    GPGME::Crypto.new.decrypt(StringIO.new(encrypted_bytes), output: output)
    output.string
  end

  # Extracts a tar.gz byte string into a hash of { entry_name => bytes }.
  def extract_tar_gz(tar_gz_bytes)
    tar_bytes = Zlib::GzipReader.new(StringIO.new(tar_gz_bytes)).read
    entries = {}
    Gem::Package::TarReader.new(StringIO.new(tar_bytes)) do |tar|
      tar.each { |entry| entries[entry.full_name] = entry.read }
    end
    entries
  end

  # Parses the metadata CSV the s3 transmitters write alongside the PDF.
  def parse_metadata_csv(csv_bytes)
    CSV.parse(csv_bytes, headers: true).first.to_h
  end

  # Returns a fresh AWS S3 client pointed at whatever endpoint the
  # transmission_method_configuration says.
  def s3_client_from(config)
    Aws::S3::Client.new(
      region: config["region"],
      access_key_id: config["aws_access_key_id"],
      secret_access_key: config["aws_secret_access_key"],
      endpoint: config["endpoint"],
      force_path_style: true,
      request_checksum_calculation: "when_required"
    )
  end
end

RSpec.configure do |config|
  config.include TransmitterRoundTrip, integration: true
end
