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

  describe "pay_frequency nullable" do
    let(:argyle_report) { build(:argyle_report, :with_argyle_account) }

    before do
      # Override the Argyle income to have nil pay_frequency (as real Argyle API returns for gig workers)
      allow(argyle_report).to receive(:incomes).and_return([
        Aggregators::ResponseObjects::Income.new(
          account_id: "argyle_report1",
          pay_frequency: nil,
          compensation_amount: 500.00,
          compensation_unit: "hourly"
        )
      ])
    end

    let(:aggregator_report) do
      Aggregators::AggregatorReports::CompositeReport.new(
        [ argyle_report ],
        days_to_fetch_for_w2: 90,
        days_to_fetch_for_gig: 90
      )
    end

    it "accepts a payload with pay_frequency null" do
      result = subject.deliver
      expect(result).to eq("ok")
    end
  end

  describe "server rejects invalid pay_frequency" do
    it "returns an error for an invalid pay_frequency value" do
      uri = URI(webhook_url)
      payload = CbvFlowToJson.new(cbv_flow, mock_client_agency, aggregator_report).to_h
      payload[:employment_records][0][:pay_frequency] = "INVALID_FREQUENCY"
      body = payload.to_json

      req = Net::HTTP::Post.new(uri)
      req.content_type = "application/json"
      req.body = body
      timestamp = Time.now.to_i.to_s
      req["X-VMI-Timestamp"] = timestamp
      req["X-VMI-Signature"] = JsonApiSignature.generate(body, timestamp, api_key)
      req["X-VMI-API-Key"] = api_key
      req["X-VMI-Confirmation-Code"] = cbv_flow.confirmation_code

      res = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(req) }

      expect(res.code).to eq("400")
      error_body = JSON.parse(res.body)
      expect(error_body["error_code"]).to eq("VALIDATION_ERROR")
    end
  end

  describe "server rejects wrong API key" do
    it "returns 401 for an incorrect API key" do
      uri = URI(webhook_url)
      payload = CbvFlowToJson.new(cbv_flow, mock_client_agency, aggregator_report).to_h
      body = payload.to_json
      wrong_key = "wrong-api-key-value"

      req = Net::HTTP::Post.new(uri)
      req.content_type = "application/json"
      req.body = body
      timestamp = Time.now.to_i.to_s
      req["X-VMI-Timestamp"] = timestamp
      req["X-VMI-Signature"] = JsonApiSignature.generate(body, timestamp, wrong_key)
      req["X-VMI-API-Key"] = wrong_key
      req["X-VMI-Confirmation-Code"] = cbv_flow.confirmation_code

      res = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(req) }

      expect(res.code).to eq("401")
      error_body = JSON.parse(res.body)
      expect(error_body["error_code"]).to eq("AUTHENTICATION_ERROR")
    end
  end
end
