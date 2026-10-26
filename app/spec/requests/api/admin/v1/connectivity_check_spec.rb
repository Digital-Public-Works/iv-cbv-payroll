require "rails_helper"

RSpec.describe "Admin API: connectivity check", type: :request do
  around { |example| with_admin_api(settings_writable: false) { example.run } }

  before { create_admin_partner! }

  it "runs the check for a stored method" do
    allow(AdminApi::ConnectivityCheck).to receive(:call).and_return(ok: true, kind: "handshake", detail: "fine")

    admin_request(:post, "/api/admin/v1/partners/admin_spec/transmission_methods/sftp/check")

    expect(response).to have_http_status(:ok)
    expect(json_body).to eq("ok" => true, "kind" => "handshake", "detail" => "fine")
  end

  it "returns 404 for a method the partner doesn't have" do
    admin_request(:post, "/api/admin/v1/partners/admin_spec/transmission_methods/webhook/check")

    expect(response).to have_http_status(:not_found)
  end
end
