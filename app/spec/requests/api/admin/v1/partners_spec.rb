require "rails_helper"

RSpec.describe "Admin API: partners", type: :request do
  let(:secret) { "test-admin-api-secret" }
  let(:actor) { "operator@digitalpublicworks.org" }
  let(:path) { "/api/admin/v1/partners" }

  def signed_headers(method: "GET", path: self.path, query: "", body: "", actor: self.actor, secret: self.secret)
    timestamp = Time.now.to_i
    {
      "X-VMI-Admin-Signature" => AdminApi::RequestSignature.sign(
        secret, method: method, path: path, query: query, timestamp: timestamp, body: body, actor: actor
      ),
      "X-VMI-Admin-Timestamp" => timestamp.to_s,
      "X-VMI-Admin-Actor" => actor
    }
  end

  around do |example|
    stub_environment_variable("ADMIN_API_SERVICE_SECRET", secret) do
      stub_environment_variable("ADMIN_API_SETTINGS_WRITABLE", nil) { example.run }
    end
  end

  context "when the admin API is not enabled" do
    around do |example|
      stub_environment_variable("ADMIN_API_SERVICE_SECRET", nil) { example.run }
    end

    it "returns 404 for a correctly signed request" do
      get path, headers: signed_headers

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 without a signature" do
      get path

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/admin/v1/partners" do
    it "lists partners for a correctly signed request" do
      get path, headers: signed_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      ids = body["partners"].map { |partner| partner["partner_id"] }
      expect(ids).to eq(PartnerConfig.order(:partner_id).pluck(:partner_id))
      expect(ids).to include("sandbox")

      sandbox = body["partners"].find { |partner| partner["partner_id"] == "sandbox" }
      expect(sandbox.keys).to contain_exactly(
        "partner_id", "name", "active_demo", "active_prod", "transmission_methods", "updated_at"
      )
      expect(sandbox["transmission_methods"]).to eq(
        PartnerConfig.find_by(partner_id: "sandbox").partner_transmission_methods.map(&:method_type).sort
      )
    end

    it "never returns transmission config values" do
      sandbox = PartnerConfig.find_by(partner_id: "sandbox")
      method = sandbox.partner_transmission_methods.first
      method.partner_transmission_configs.create!(is_encrypted: true, key: "password", value: "super-secret-value")

      get path, headers: signed_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("super-secret-value")
    end

    it "reports settings as read-only when ADMIN_API_SETTINGS_WRITABLE is unset" do
      get path, headers: signed_headers

      expect(JSON.parse(response.body)["meta"]).to eq("settings_writable" => false)
    end

    it "reports settings as writable when ADMIN_API_SETTINGS_WRITABLE is true" do
      stub_environment_variable("ADMIN_API_SETTINGS_WRITABLE", "true") do
        get path, headers: signed_headers
      end

      expect(JSON.parse(response.body)["meta"]).to eq("settings_writable" => true)
    end

    it "accepts a signed query string" do
      get "#{path}?b=2&a=1", headers: signed_headers(query: "a=1&b=2")

      expect(response).to have_http_status(:ok)
    end

    it "returns 401 without a signature" do
      get path

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)).to eq("errors" => [ { "message" => "Unauthorized" } ])
    end

    it "returns 401 for a signature made with another secret" do
      get path, headers: signed_headers(secret: "wrong-secret")

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 when the actor header is changed after signing" do
      get path, headers: signed_headers.merge("X-VMI-Admin-Actor" => "someone-else@digitalpublicworks.org")

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 when the query is changed after signing" do
      get "#{path}?a=2", headers: signed_headers(query: "a=1")

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 for a HEAD request carrying a GET signature" do
      head path, headers: signed_headers

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 for a stale timestamp" do
      headers = signed_headers
      travel 6.minutes do
        get path, headers: headers
      end

      expect(response).to have_http_status(:unauthorized)
    end

    # The ALB blocks `/api/admin/*` by exact prefix. Rails squeezes repeated
    # slashes when routing, so `/api//admin/...` would reach the controller.
    it "returns 404 for a path the public load balancer wouldn't block" do
      odd_path = "/api//admin/v1/partners"
      get odd_path, headers: signed_headers(path: odd_path)

      expect(response).to have_http_status(:not_found)
    end
  end
end
