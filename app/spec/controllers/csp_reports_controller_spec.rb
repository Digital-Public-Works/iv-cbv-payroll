require 'rails_helper'

RSpec.describe CspReportsController, type: :controller do
  describe 'POST #create' do
    let(:valid_csp_report) do
      {
        "csp-report" => {
          "document-uri" => "https://example.com/page",
          "violated-directive" => "style-src 'self'",
          "blocked-uri" => "inline",
          "source-file" => "https://example.com/script.js",
          "line-number" => 10,
          "column-number" => 5,
          "original-policy" => "style-src 'self'; script-src 'self'"
        }
      }
    end

    context 'with a valid CSP report' do
      it 'returns no_content status' do
        post :create, body: valid_csp_report.to_json

        expect(response).to have_http_status(:no_content)
      end

      it 'records a custom event in New Relic' do
        expect(NewRelic::Agent).to receive(:record_custom_event).with(
          "CSPViolation",
          hash_including(
            document_uri: "https://example.com/page",
            violated_directive: "style-src 'self'",
            blocked_uri: "inline"
          )
        )

        post :create, body: valid_csp_report.to_json
      end

      it 'logs the violation to Rails logger' do
        expect(Rails.logger).to receive(:warn).with(
          "[CSP Violation] style-src 'self' - blocked: inline"
        )

        post :create, body: valid_csp_report.to_json
      end
    end

    context 'with malformed JSON' do
      it 'returns bad_request status' do
        post :create, body: "not valid json"

        expect(response).to have_http_status(:bad_request)
      end

      it 'logs the parse error' do
        expect(Rails.logger).to receive(:error).with(/\[CSP Report\] JSON parse error:/)
        expect(Rails.logger).to receive(:error).with(/\[CSP Report\] Received malformed or empty CSP report/)

        post :create, body: "not valid json"
      end

      it 'does not record a New Relic event' do
        expect(NewRelic::Agent).not_to receive(:record_custom_event)

        post :create, body: "not valid json"
      end
    end

    context 'with valid JSON but missing csp-report key' do
      it 'returns bad_request status' do
        post :create, body: { "other-key" => "value" }.to_json

        expect(response).to have_http_status(:bad_request)
      end

      it 'logs the malformed report' do
        expect(Rails.logger).to receive(:error).with(
          "[CSP Report] Received malformed or empty CSP report"
        )

        post :create, body: { "other-key" => "value" }.to_json
      end

      it 'does not record a New Relic event' do
        expect(NewRelic::Agent).not_to receive(:record_custom_event)

        post :create, body: { "other-key" => "value" }.to_json
      end
    end

    context 'with empty csp-report' do
      it 'returns bad_request status' do
        post :create, body: { "csp-report" => {} }.to_json

        expect(response).to have_http_status(:bad_request)
      end
    end

    it 'handles missing CSRF token gracefully via null_session' do
      # Browsers send CSP reports without CSRF tokens
      # Using protect_from_forgery with: :null_session allows the request
      # to proceed with a nullified session instead of raising an exception
      post :create, body: valid_csp_report.to_json

      expect(response).to have_http_status(:no_content)
    end
  end
end
