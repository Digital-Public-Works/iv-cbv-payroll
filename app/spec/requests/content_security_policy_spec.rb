require "rails_helper"

# Regression coverage for the CSP nonce generator.
#
# The nonce was previously derived from `request.session.id`, which is nil on a
# visitor's very first request (the cookie session isn't established until the
# response is sent). That produced an empty `'nonce-'` in the CSP header and
# caused browsers to block New Relic's inline browser-agent scripts on the
# initial page load. The generator now uses `SecureRandom.base64(16)`, which
# yields a valid, non-empty nonce on every request.
#
# See app/config/initializers/content_security_policy.rb
RSpec.describe "Content Security Policy nonce", type: :request do
  # Pull the script-src nonce out of the enforced CSP header.
  def csp_script_nonce(response)
    header = response.headers["Content-Security-Policy"]
    match = header&.match(/script-src[^;]*'nonce-([^']*)'/)
    match && match[1]
  end

  describe "on a first-time visitor's first request" do
    it "sets a non-empty nonce in the Content-Security-Policy header" do
      # No cookies are sent, so no session exists yet — this is the exact
      # condition that produced an empty nonce under the old generator.
      get "/"

      expect(response).to have_http_status(:success)
      nonce = csp_script_nonce(response)
      expect(nonce).to be_present
      expect(response.headers["Content-Security-Policy"]).not_to include("'nonce-'")
    end

    it "generates the nonce with SecureRandom.base64(16)" do
      get "/"

      nonce = csp_script_nonce(response)
      # SecureRandom.base64(16) encodes 16 random bytes as standard base64.
      expect(nonce).to match(%r{\A[A-Za-z0-9+/]+={0,2}\z})
      expect(Base64.strict_decode64(nonce).bytesize).to eq(16)
    end
  end

  describe "per-request uniqueness" do
    it "generates a different nonce on each request" do
      get "/"
      first_nonce = csp_script_nonce(response)

      get "/"
      second_nonce = csp_script_nonce(response)

      expect(first_nonce).to be_present
      expect(second_nonce).to be_present
      expect(second_nonce).not_to eq(first_nonce)
    end
  end

  describe "nonce-dependent view helpers" do
    it "stamps the same nonce on csp_meta_tag as the CSP header advertises" do
      get "/"

      header_nonce = csp_script_nonce(response)
      meta_match = response.body.match(/<meta name="csp-nonce" content="([^"]*)"/)

      expect(header_nonce).to be_present
      expect(meta_match).to be_present, "expected a csp-nonce meta tag in the response body"
      expect(meta_match[1]).to eq(header_nonce)
    end
  end
end
