# @see: https://github.com/ueno/ruby-gpgme
require "gpgme"
require "aws-sdk-s3"

class S3Service
  def initialize(config)
    @bucket_name      = config["bucket"]
    @region           = config["region"]
    @access_key       = config["aws_access_key_id"]
    @secret_key       = config["aws_secret_access_key"]
    # Only set for s3proxy in integration tests; production talks to real AWS S3 without these.
    @endpoint         = config["endpoint"]
    @force_path_style = config["force_path_style"]
  end

  def upload_file(file_path, file_name)
    File.open(file_path, "rb") do |file|
      s3_client.put_object(bucket: @bucket_name, key: file_name, body: file)
    end
  end

  private

  def s3_client
    client_opts = {}
    client_opts[:region] = @region if @region.present?
    if @access_key.present? && @secret_key.present?
      client_opts[:access_key_id] = @access_key
      client_opts[:secret_access_key] = @secret_key
    end
    if @endpoint.present?
      client_opts[:endpoint] = @endpoint
      # s3proxy (used in integration tests) does not handle checksum's well https://github.com/gaul/s3proxy/issues/922
      client_opts[:request_checksum_calculation] = "when_required"
    end
    client_opts[:force_path_style] = true if @force_path_style
    Aws::S3::Client.new(client_opts)
  end
end
