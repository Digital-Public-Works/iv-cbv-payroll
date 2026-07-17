require 'rails_helper'

RSpec.describe Transmitters::JsonTransmitter do
  completed_at = Time.find_zone("UTC").local(2025, 5, 1, 1)
  let(:cbv_applicant) { create(:cbv_applicant, case_number: "ABC1234") }
  let(:cbv_flow) do
    create(:cbv_flow,
      :invited,
      :with_pinwheel_account,
      cbv_applicant: cbv_applicant,
      consented_to_authorized_use_at: completed_at,
      confirmation_code: "ABC123"
    )
  end
  let(:transmission_method_configuration) { {
    "url" => "http://fake-state.api.gov/api/v1/income-report" # Should be replaced with real agency sandbox url!
  } }

  let(:mock_client_agency) do
    instance_double(ClientAgencyConfig::ClientAgency, include_full_ssn: false, include_direct_deposit_last_4: false)
  end

  let(:pinwheel_report) { build(:pinwheel_report, :with_pinwheel_account) }
  let(:argyle_report) { build(:argyle_report, :with_argyle_account) }
  let(:aggregator_report) { Aggregators::AggregatorReports::CompositeReport.new(
    [ pinwheel_report, argyle_report ],
    days_to_fetch_for_w2: 90,
    days_to_fetch_for_gig: 90
  ) }

  let!(:service_user) { create(:user, client_agency_id: "sandbox", is_service_account: true) }
  let!(:api_token) { create(:api_access_token, user: service_user) }

  before do
    allow(mock_client_agency).to receive(:id).and_return("sandbox")
    allow(mock_client_agency).to receive(:include_paystubs).and_return(false)
    allow(CbvApplicant).to receive(:valid_attributes_for_agency).with("sandbox").and_return([ "case_number" ])
    allow(Rails.logger).to receive(:error)
  end

  context 'agency responds with 200' do
    it 'posts to the endpoint with the expected data' do
      expect(aggregator_report).to receive(:income_report).and_return({ cool: "report" })
      VCR.use_cassette("json_transmitter_200") do
        described_class.new(cbv_flow, mock_client_agency, aggregator_report, transmission_method_configuration).deliver
      end
    end
  end

  context 'agency responds with 500' do
    it 'raises an HTTP error' do
      VCR.use_cassette("json_transmitter_500") do
        expect { described_class.new(cbv_flow, mock_client_agency, aggregator_report, transmission_method_configuration).deliver }.to raise_error("Unexpected response from agency: 500 Internal Server Error")
      end

      expect(Rails.logger).to have_received(:error).with(/Unexpected response: 500/)
    end
  end

  context 'any other non-200 response' do
    it 'raises an HTTP error' do
      VCR.use_cassette("json_transmitter_418") do
        expect { described_class.new(cbv_flow, mock_client_agency, aggregator_report, transmission_method_configuration).deliver }
          .to raise_error("Unexpected response from agency: 418 I'm a teapot")
      end

      expect(Rails.logger).to have_received(:error).with(/Unexpected response: 418/)
      expect(Rails.logger).to have_received(:error).with(/Here is my handle, here is my spout./)
    end
  end

  context 'signature generation' do
    it 'generates signature with the request body' do
      expect(JsonApiSignature).to receive(:generate).with(
        a_string_including(cbv_flow.confirmation_code),
        anything,
        anything
      ).and_return("mock-signature")

      VCR.use_cassette("json_transmitter_200") do
        described_class.new(cbv_flow, mock_client_agency, aggregator_report, transmission_method_configuration).deliver
      end
    end

    context 'with multiple API keys' do
      let!(:older_token) { create(:api_access_token, user: service_user, created_at: 2.days.ago) }
      let!(:newer_token) { create(:api_access_token, user: service_user, created_at: 1.day.ago) }

      it 'uses the oldest active API key' do
        expect(JsonApiSignature).to receive(:generate).with(anything, anything, older_token.access_token).and_return("mock-signature")

        VCR.use_cassette("json_transmitter_200") do
          described_class.new(cbv_flow, mock_client_agency, aggregator_report, transmission_method_configuration).deliver
        end
      end
    end
  end

  context 'custom headers' do
    let(:transmission_method_configuration) do
      {
        "url" => "http://fake-state.api.gov/api/v1/income-report",
        "custom_headers" => {
          "X-Client-ID" => "test-client-id",
          "X-Request-ID" => "test-request-id"
        }
      }
    end

    it 'sends configured custom headers' do
      stub = stub_request(:post, "http://fake-state.api.gov/api/v1/income-report")
        .with(headers: { 'X-Client-ID' => 'test-client-id', 'X-Request-ID' => 'test-request-id' })
        .to_return(status: 200, body: '{"status": "success"}')

      expect(described_class.new(cbv_flow, mock_client_agency, aggregator_report, transmission_method_configuration).deliver).to eq("ok")
      expect(stub).to have_been_requested
    end
  end

  context 'include_paystubs' do
    let(:paystubs_url) { "http://fake.example.org/api/v1/income-report" }
    let(:paystubs_config) { { "url" => paystubs_url } }
    let(:paystubs_result) do
      Aggregators::PaystubsPdfService::Result.new(
        content: "fake-paystubs-pdf", page_count: 5, file_size: 18
      )
    end

    before do
      allow(mock_client_agency).to receive(:argyle_environment).and_return("sandbox")
    end

    context "when the partner has include_paystubs disabled" do
      before { allow(mock_client_agency).to receive(:include_paystubs).and_return(false) }

      it "does not include paystub_pdf in the payload" do
        stub = stub_request(:post, paystubs_url)
          .with { |req| !JSON.parse(req.body).key?("paystub_pdf") }
          .to_return(status: 200, body: '{"status": "ok"}')

        described_class.new(cbv_flow, mock_client_agency, aggregator_report, paystubs_config).deliver
        expect(stub).to have_been_requested
      end
    end

    context "when the partner has include_paystubs enabled" do
      before do
        allow(mock_client_agency).to receive(:include_paystubs).and_return(true)
        allow_any_instance_of(Aggregators::PaystubsPdfService)
          .to receive(:generate).and_return(paystubs_result)
      end

      it "includes paystub_pdf (base64) in the payload" do
        captured_body = nil
        stub_request(:post, paystubs_url)
          .with { |req| captured_body = JSON.parse(req.body); true }
          .to_return(status: 200, body: '{"status": "ok"}')

        described_class.new(cbv_flow, mock_client_agency, aggregator_report, paystubs_config).deliver
        expect(captured_body["paystub_pdf"]).to eq(Base64.strict_encode64("fake-paystubs-pdf"))
      end
    end
  end
end
