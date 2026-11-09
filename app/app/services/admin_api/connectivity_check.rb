require "net/http"

# No-op connectivity check for one transmission method, using its stored
# credentials: SFTP login plus a stat of path_prefix, S3 HeadBucket (and a GPG
# key parse when s3 has a public_key), or an OPTIONS/HEAD request for webhook and json.
# shared_email can't be checked without sending mail. Nothing is uploaded,
# posted or sent; it's a guard against mistyped credentials and unreachable
# endpoints, not proof that delivery will succeed.
module AdminApi
  class ConnectivityCheck
    TIMEOUT = 10

    def self.call(transmission_method)
      new(transmission_method).call
    end

    def initialize(transmission_method)
      @type = transmission_method.method_type
      # Decrypted, as the transmitters read it.
      @config = transmission_method.partner_transmission_configs.to_h { |c| [ c.key, c.value ] }
    end

    def call
      case @type
      when "sftp" then sftp
      when "s3" then s3
      when "webhook" then http(@config["webhook_url"])
      when "json" then http(@config["url"])
      else result(false, "not_applicable", "Email delivery can't be checked without sending mail")
      end
    rescue StandardError => e
      result(false, kind, "#{e.class}: #{e.message}".truncate(300))
    end

    private

    def kind
      %w[webhook json].include?(@type) ? "reachability" : "handshake"
    end

    def result(ok, kind, detail)
      { ok: ok, kind: kind, detail: detail }
    end

    def sftp
      url, user = @config.values_at("url", "user")
      return result(false, "handshake", "url and user are required") if url.blank? || user.blank?

      port = (@config["port"].presence || 22).to_i
      directory = @config["path_prefix"].presence || "."
      Net::SSH.start(url, user, password: @config["password"], port: port, keys: [],
                     auth_methods: %w[password keyboard-interactive], non_interactive: true, timeout: TIMEOUT) do |session|
        sftp = Net::SFTP::Session.new(session)
        sftp.connect!
        sftp.stat!(directory)
        sftp.close_channel
      end
      result(true, "handshake", "Connected to #{url}:#{port} as #{user}; #{directory} exists")
    end

    # With a public_key, the key must parse (uploads are encrypted to it);
    # without one, uploads go unencrypted and the detail says so.
    def s3
      return result(false, "handshake", "No bucket configured") if @config["bucket"].blank?

      key = @config["public_key"]
      if key.present?
        fingerprint = GPGME::Key.import(key).imports.first&.fingerprint
        return result(false, "handshake", "public_key is not a GPG public key") if fingerprint.blank?
      end

      S3Service.new(@config).head_bucket
      encryption = fingerprint ? "encrypting to GPG key #{fingerprint}" : "no public_key, so uploads are not encrypted"
      result(true, "handshake", "HeadBucket succeeded for #{@config['bucket']}; #{encryption}")
    end

    def http(raw_url)
      uri = URI.parse(raw_url.to_s)
      return result(false, "reachability", "No valid http(s) URL configured") unless uri.is_a?(URI::HTTP) && uri.host.present?

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        response = http.request(Net::HTTP::Options.new(uri))
        verb = "OPTIONS"
        if %w[405 501].include?(response.code)
          response = http.request(Net::HTTP::Head.new(uri))
          verb = "HEAD"
        end
        ok = response.code.to_i < 500
        result(ok, "reachability", "#{verb} #{uri.host} answered #{response.code} (reachability, not delivery)")
      end
    end
  end
end
