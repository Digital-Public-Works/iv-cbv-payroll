require "rails_helper"

RSpec.describe Transmitters::WebhookTransmitter, integration: true do
  let(:completed_at) { Time.find_zone("UTC").local(2025, 5, 1, 1) }
  let(:cbv_applicant) { create(:cbv_applicant, case_number: "ABC1234") }
  let(:cbv_flow) do
    create(:cbv_flow,
      :invited,
      :with_pinwheel_account,
      cbv_applicant: cbv_applicant,
      consented_to_authorized_use_at: completed_at,
      confirmation_code: "WEBHOOK123"
    )
  end

  let(:webhook_url) { "http://localhost:9292/api/v1/income-report" }
  let(:api_key) { ENV.fetch("WEBHOOK_TEST_API_KEY", "my-secure-guid") }
  let(:transmission_method_configuration) do
    {
      "webhook_url" => webhook_url,
      "api_key" => api_key
    }
  end

  let(:mock_client_agency) { instance_double(ClientAgencyConfig::ClientAgency) }
  let(:pinwheel_report) { build(:pinwheel_report, :with_pinwheel_account) }
  let(:aggregator_report) do
    Aggregators::AggregatorReports::CompositeReport.new(
      [ pinwheel_report ],
      days_to_fetch_for_w2: 90,
      days_to_fetch_for_gig: 90
    )
  end

  before do
    allow(mock_client_agency).to receive(:transmission_method_configuration).and_return(transmission_method_configuration)
    allow(mock_client_agency).to receive(:id).and_return("sandbox")
    allow(CbvApplicant).to receive(:valid_attributes_for_agency).with("sandbox").and_return([ "case_number" ])

    WebMock.allow_net_connect!
  end

  after do
    WebMock.disable_net_connect!
  end

  subject { described_class.new(cbv_flow, mock_client_agency, aggregator_report) }

  describe "#deliver" do
    it "successfully delivers to a running reference server" do
      result = subject.deliver
      expect(result).to eq("ok")
    end

    it "sends a valid JSON payload with expected top-level keys" do
      # Capture the request body by wrapping Net::HTTP
      sent_body = nil
      allow(Net::HTTP).to receive(:start).and_wrap_original do |original, *args, **kwargs, &block|
        original.call(*args, **kwargs) do |http|
          allow(http).to receive(:request).and_wrap_original do |orig_request, req|
            sent_body = req.body
            orig_request.call(req)
          end
          block.call(http)
        end
      end

      subject.deliver

      payload = JSON.parse(sent_body)
      expect(payload).to have_key("report_metadata")
      expect(payload).to have_key("client_information")
      expect(payload).to have_key("employment_records")
    end
  end
end
