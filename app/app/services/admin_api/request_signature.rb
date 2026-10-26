require "openssl"
require "digest"
require "active_support/security_utils"

# Signs and verifies requests to the admin API (VMI-ADMIN-HMAC-V1).
#
# This is deliberately separate from JsonApiSignature, which signs only
# `timestamp:body` and is shared with the json/webhook transmitters. Here the
# signature covers the method, path and query, timestamp, body and actor, so a
# captured signature can't be replayed onto another path or another operator.
#
# The canonical string is one field per line:
#
#   VMI-ADMIN-HMAC-V1
#   <HTTP method, uppercase>
#   <path, with the query string's pairs sorted>
#   <timestamp, Unix seconds>
#   <hex SHA-256 of the raw body>
#   <actor header value>
#
# spec/fixtures/admin_api/signing_vectors.json holds known-good examples that
# the vmi-admin portal's signer is tested against, so the two can't drift.
module AdminApi
  class RequestSignature
    VERSION = "VMI-ADMIN-HMAC-V1"
    SIGNATURE_HEADER = "X-VMI-Admin-Signature"
    TIMESTAMP_HEADER = "X-VMI-Admin-Timestamp"
    ACTOR_HEADER = "X-VMI-Admin-Actor"
    MAX_CLOCK_SKEW = 5.minutes

    def self.canonical_string(method:, path:, query:, timestamp:, body:, actor:)
      [
        VERSION,
        method.to_s.upcase,
        canonical_path(path, query),
        timestamp.to_s,
        Digest::SHA256.hexdigest(body.to_s),
        actor.to_s
      ].join("\n")
    end

    # Query pairs are sorted as raw (still percent-encoded) strings, by key and
    # then by value, so both sides agree without having to agree on decoding.
    def self.canonical_path(path, query)
      pairs = query.to_s.split("&").reject(&:empty?)
      return path if pairs.empty?

      sorted = pairs.sort_by { |pair| key, value = pair.split("=", 2); [ key, value.to_s ] }
      "#{path}?#{sorted.join("&")}"
    end

    def self.sign(secret, **fields)
      OpenSSL::HMAC.hexdigest("SHA256", secret, canonical_string(**fields))
    end

    # Returns true only for a fresh, correctly signed request. It never says
    # which check failed; callers respond with a bare 401.
    def self.valid_request?(request, secret, now: Time.now)
      signature = request.headers[SIGNATURE_HEADER].to_s
      timestamp = request.headers[TIMESTAMP_HEADER].to_s
      actor = request.headers[ACTOR_HEADER].to_s
      return false if signature.empty? || actor.empty?
      return false unless timestamp.match?(/\A\d{1,12}\z/)
      return false if (now.to_i - timestamp.to_i).abs > MAX_CLOCK_SKEW.to_i

      expected = sign(
        secret,
        method: request.request_method,
        path: request.path,
        query: request.query_string,
        timestamp: timestamp,
        body: request.raw_post,
        actor: actor
      )
      ActiveSupport::SecurityUtils.secure_compare(signature, expected)
    end
  end
end
