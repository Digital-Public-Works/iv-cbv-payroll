require "rails_helper"

RSpec.describe Transmitters::WebhookTransmitter do
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

  let(:webhook_url) { "http://fake-state.api.gov/api/v1/webhook" }
  let(:api_key) { "test-webhook-api-key" }
  let(:transmission_method_configuration) do
    {
      "webhook_url" => webhook_url,
      "api_key" => api_key
    }
  end

  let(:mock_client_agency) { instance_double(ClientAgencyConfig::ClientAgency) }
  let(:pinwheel_report) { build(:pinwheel_report, :with_pinwheel_account) }
  let(:argyle_report) { build(:argyle_report, :with_argyle_account) }
  let(:aggregator_report) do
    Aggregators::AggregatorReports::CompositeReport.new(
      [ pinwheel_report, argyle_report ],
      days_to_fetch_for_w2: 90,
      days_to_fetch_for_gig: 90
    )
  end

  before do
    allow(mock_client_agency).to receive(:id).and_return("sandbox")
    allow(CbvApplicant).to receive(:valid_attributes_for_agency).with("sandbox").and_return([ "case_number" ])
    allow(Rails.logger).to receive(:error)
  end

  subject { described_class.new(cbv_flow, mock_client_agency, aggregator_report, transmission_method_configuration) }

  describe "#deliver" do
    context "when agency responds with 200" do
      before do
        stub_request(:post, webhook_url).to_return(status: 200, body: '{"status": "ok"}')
      end

      it "returns ok" do
        expect(subject.deliver).to eq("ok")
      end

      it "sends correct X-VMI headers" do
        freeze_time do
          expected_timestamp = Time.now.to_i.to_s

          stub = stub_request(:post, webhook_url)
            .with(headers: {
              "X-VMI-Timestamp" => expected_timestamp,
              "X-VMI-API-Key" => api_key,
              "X-VMI-Confirmation-Code" => "WEBHOOK123",
              "Content-Type" => "application/json"
            })
            .to_return(status: 200, body: '{"status": "ok"}')

          subject.deliver
          expect(stub).to have_been_requested
        end
      end

      it "sends a JSON body with report_metadata, client_information, and employment_records" do
        stub = stub_request(:post, webhook_url)
          .with { |request|
            body = JSON.parse(request.body)
            body.key?("report_metadata") &&
              body.key?("client_information") &&
              body.key?("employment_records")
          }
          .to_return(status: 200, body: '{"status": "ok"}')

        subject.deliver
        expect(stub).to have_been_requested
      end
    end

    context "when agency responds with 500" do
      before do
        stub_request(:post, webhook_url).to_return(status: 500, body: "Internal Server Error")
      end

      it "raises an error" do
        expect { subject.deliver }.to raise_error(/Unexpected response from agency: 500/)
        expect(Rails.logger).to have_received(:error).with(/Unexpected response: 500/)
      end
    end

    context "when agency responds with 418" do
      before do
        stub_request(:post, webhook_url).to_return(status: 418, body: "I'm a teapot")
      end

      it "raises an error" do
        expect { subject.deliver }.to raise_error(/Unexpected response from agency: 418/)
        expect(Rails.logger).to have_received(:error).with(/Unexpected response: 418/)
      end
    end

    context "signature generation" do
      it "generates signature via JsonApiSignature with the request body" do
        expect(JsonApiSignature).to receive(:generate).with(
          a_string_including("WEBHOOK123"),
          anything,
          api_key
        ).and_return("mock-signature")

        stub_request(:post, webhook_url).to_return(status: 200, body: '{"status": "ok"}')
        subject.deliver
      end
    end
  end
end
