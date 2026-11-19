require "rails_helper"

RSpec.describe AdminApi::RequestSignature do
  let(:secret) { "test-admin-api-secret" }
  let(:now) { Time.at(1_760_889_600) }
  let(:actor) { "operator@digitalpublicworks.org" }

  describe "shared vectors" do
    # The vmi-admin portal's signer is tested against the same file.
    vectors = JSON.parse(File.read(Rails.root.join("spec/fixtures/admin_api/signing_vectors.json")))

    vectors["vectors"].map { |vector| vector.merge("secret" => vectors["secret"]) }.each do |vector|
      it "reproduces the canonical string and signature for: #{vector["name"]}" do
        fields = {
          method: vector["method"],
          path: vector["path"],
          query: vector["query"],
          timestamp: vector["timestamp"],
          body: vector["body"],
          actor: vector["actor"]
        }

        expect(described_class.canonical_string(**fields)).to eq(vector["canonical_string"])
        expect(described_class.sign(vector["secret"], **fields)).to eq(vector["signature"])
      end
    end
  end

  describe ".valid_request?" do
    def signed_headers(method:, path:, query: "", body: "", timestamp: now.to_i, actor: self.actor)
      signature = described_class.sign(secret, method: method, path: path, query: query,
                                               timestamp: timestamp, body: body, actor: actor)
      {
        "HTTP_X_VMI_ADMIN_SIGNATURE" => signature,
        "HTTP_X_VMI_ADMIN_TIMESTAMP" => timestamp.to_s,
        "HTTP_X_VMI_ADMIN_ACTOR" => actor
      }
    end

    def build_request(method:, path:, query: "", body: "", headers: {})
      uri = query.empty? ? path : "#{path}?#{query}"
      env = Rack::MockRequest.env_for(uri, method: method, input: body).merge(headers)
      ActionDispatch::Request.new(env)
    end

    def valid?(request)
      described_class.valid_request?(request, secret, now: now)
    end

    let(:path) { "/api/admin/v1/partners/sandbox/validate" }
    let(:body) { '{"settings":{"name":"Sandbox"}}' }
    let(:headers) { signed_headers(method: "POST", path: path, query: "b=2&a=1", body: body) }

    it "accepts a correctly signed, fresh request" do
      expect(valid?(build_request(method: "POST", path: path, query: "b=2&a=1", body: body, headers: headers))).to be(true)
    end

    it "accepts the query string in any order" do
      expect(valid?(build_request(method: "POST", path: path, query: "a=1&b=2", body: body, headers: headers))).to be(true)
    end

    it "rejects a changed method" do
      expect(valid?(build_request(method: "PUT", path: path, query: "b=2&a=1", body: body, headers: headers))).to be(false)
    end

    it "rejects a changed path" do
      expect(valid?(build_request(method: "POST", path: "/api/admin/v1/partners/other/validate", query: "b=2&a=1", body: body, headers: headers))).to be(false)
    end

    it "rejects a changed query" do
      expect(valid?(build_request(method: "POST", path: path, query: "b=2&a=2", body: body, headers: headers))).to be(false)
    end

    it "rejects a changed body" do
      expect(valid?(build_request(method: "POST", path: path, query: "b=2&a=1", body: '{"settings":{"name":"Evil"}}', headers: headers))).to be(false)
    end

    it "rejects a changed actor" do
      tampered = headers.merge("HTTP_X_VMI_ADMIN_ACTOR" => "someone-else@digitalpublicworks.org")
      expect(valid?(build_request(method: "POST", path: path, query: "b=2&a=1", body: body, headers: tampered))).to be(false)
    end

    it "rejects a GET signature replayed to a different GET path" do
      get_headers = signed_headers(method: "GET", path: "/api/admin/v1/partners")
      expect(valid?(build_request(method: "GET", path: "/api/admin/v1/audit", headers: get_headers))).to be(false)
    end

    it "rejects a signature made with a different secret" do
      forged = headers.merge("HTTP_X_VMI_ADMIN_SIGNATURE" => described_class.sign(
        "wrong-secret", method: "POST", path: path, query: "b=2&a=1", timestamp: now.to_i, body: body, actor: actor
      ))
      expect(valid?(build_request(method: "POST", path: path, query: "b=2&a=1", body: body, headers: forged))).to be(false)
    end

    it "accepts a timestamp at the edge of the 5-minute window" do
      edge = signed_headers(method: "GET", path: "/api/admin/v1/partners", timestamp: now.to_i - 300)
      expect(valid?(build_request(method: "GET", path: "/api/admin/v1/partners", headers: edge))).to be(true)
    end

    it "rejects timestamps more than 5 minutes old or ahead" do
      [ now.to_i - 301, now.to_i + 301 ].each do |timestamp|
        stale = signed_headers(method: "GET", path: "/api/admin/v1/partners", timestamp: timestamp)
        expect(valid?(build_request(method: "GET", path: "/api/admin/v1/partners", headers: stale))).to be(false)
      end
    end

    it "rejects a non-numeric timestamp" do
      odd = signed_headers(method: "GET", path: "/api/admin/v1/partners", timestamp: "1760889600.0")
      expect(valid?(build_request(method: "GET", path: "/api/admin/v1/partners", headers: odd))).to be(false)
    end

    %w[HTTP_X_VMI_ADMIN_SIGNATURE HTTP_X_VMI_ADMIN_TIMESTAMP HTTP_X_VMI_ADMIN_ACTOR].each do |header|
      it "rejects a request missing #{header}" do
        incomplete = signed_headers(method: "GET", path: "/api/admin/v1/partners").except(header)
        expect(valid?(build_request(method: "GET", path: "/api/admin/v1/partners", headers: incomplete))).to be(false)
      end
    end
  end
end
