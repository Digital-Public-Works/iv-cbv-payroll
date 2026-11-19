require "rails_helper"

# What the admin API leaves in the application log, which is kept for years:
# request bodies are filtered, and a malformed body is never echoed back.
RSpec.describe "Admin API: request logging", type: :request do
  let(:base) { "/api/admin/v1/partners/admin_spec" }
  let(:log) { StringIO.new }

  before { create_admin_partner! }

  around { |example| with_admin_api(settings_writable: true) { example.run } }

  # At production's level: Rails also dumps an unparseable body at debug.
  around do |example|
    capture = ActiveSupport::Logger.new(log, level: :info)
    Rails.logger.broadcast_to(capture)
    example.run
  ensure
    Rails.logger.stop_broadcasting_to(capture)
  end

  it "answers malformed JSON with a generic error, without logging the body" do
    # The parser quotes the input from where it fails, so the secret follows it.
    admin_request(:patch, base, raw_body: '{"credentials": {"configs": [{"key": "password", "value": leaky-secret-123}]}}')

    expect(response).to have_http_status(:unprocessable_content)
    expect(json_body["message"]).to eq("The request body is not valid JSON")
    expect(log.string).not_to include("leaky-secret-123")
  end

  it "filters weekly report recipients from the logged parameters" do
    admin_request(:patch, base, body: { credentials: { weekly_report_recipients: "staff-person@agency.example" }, updated_at: admin_version("admin_spec") })

    expect(log.string).to include("Parameters:")
    expect(log.string).not_to include("staff-person@agency.example")
  end
end
