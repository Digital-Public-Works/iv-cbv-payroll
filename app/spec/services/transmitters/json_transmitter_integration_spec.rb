require "rails_helper"

RSpec.describe Transmitters::JsonTransmitter, integration: true do
  let(:cbv_applicant) { create(:cbv_applicant, case_number: "JSON001") }
  let(:cbv_flow) do
    create(:cbv_flow,
      :invited,
      :with_argyle_account,
      cbv_applicant: cbv_applicant,
      consented_to_authorized_use_at: Time.current,
      confirmation_code: "JSON001",
      client_agency_id: "sandbox"
    )
  end

  let(:mock_client_agency) { instance_double(ClientAgencyConfig::ClientAgency) }
  let(:argyle_report) { build(:argyle_report, :with_argyle_account) }
  let(:aggregator_report) do
    Aggregators::AggregatorReports::CompositeReport.new(
      [ argyle_report ],
      days_to_fetch_for_w2: 90,
      days_to_fetch_for_gig: 90
    )
  end

  # Must match the JSON_API_KEY env var on the json-api Docker service
  let(:api_key) { "test-json-api-key" }

  let(:transmission_config) do
    {
      "url" => "http://localhost:4567",
      "include_report_pdf" => false
    }
  end

  before do
    allow(mock_client_agency).to receive(:id).and_return("sandbox")
    allow(mock_client_agency).to receive(:logo_path).and_return("")
    allow(mock_client_agency).to receive(:report_customization_show_earnings_list).and_return(true)
    allow(User).to receive(:api_key_for_agency).with("sandbox").and_return(api_key)
    allow(CbvApplicant).to receive(:valid_attributes_for_agency).with("sandbox").and_return([ "case_number" ])

    # Stub PDF generation — we're testing JSON transmission, not PDF rendering
    allow_any_instance_of(PdfService).to receive(:generate)
      .and_return(OpenStruct.new(content: "fake-pdf-content"))

    WebMock.allow_net_connect!
  end

  after do
    WebMock.disable_net_connect!
  end

  subject { described_class.new(cbv_flow, mock_client_agency, aggregator_report, transmission_config) }

  describe "#deliver" do
    it "successfully posts JSON to the receiver with valid signature" do
      result = subject.deliver
      expect(result).to eq("ok")
    end

    context "with report PDF included" do
      let(:transmission_config) do
        {
          "url" => "http://localhost:4567",
          "include_report_pdf" => true
        }
      end

      it "includes base64-encoded PDF in the payload" do
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
        expect(payload).to have_key("report_pdf")
        expect(payload["report_pdf"]).to be_a(String)
      end
    end

    context "with custom headers" do
      let(:transmission_config) do
        {
          "url" => "http://localhost:4567",
          "include_report_pdf" => false,
          "custom_headers" => { "X-Custom-Agency" => "sandbox-test" }
        }
      end

      it "sends custom headers along with the request" do
        sent_headers = nil
        allow(Net::HTTP).to receive(:start).and_wrap_original do |original, *args, **kwargs, &block|
          original.call(*args, **kwargs) do |http|
            allow(http).to receive(:request).and_wrap_original do |orig_request, req|
              sent_headers = req.to_hash
              orig_request.call(req)
            end
            block.call(http)
          end
        end

        subject.deliver

        expect(sent_headers["x-custom-agency"]).to include("sandbox-test")
      end
    end
  end
end
