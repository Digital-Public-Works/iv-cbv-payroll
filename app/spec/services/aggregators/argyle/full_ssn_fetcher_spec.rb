  require "rails_helper"

  RSpec.describe Aggregators::Argyle::FullSsnFetcher do
    let(:argyle_service) { instance_double(Aggregators::Sdk::ArgyleService) }
    let(:event_logger) { instance_double(GenericEventTracker, track: nil) }
    let(:cbv_flow_id) { 1011 }
    let(:client_agency_id) { "sandbox" }
    let(:account_id) { "test_argyle_account_id" }

    subject(:fetcher) do
      described_class.new(argyle_service: argyle_service, event_logger: event_logger)
    end

    describe "#fetch" do
      context "unmasked SSN" do
        before do
          allow(argyle_service).to receive(:fetch_identities_api)
            .with(account: account_id)
            .and_return("results" => [ { "ssn" => "123-45-6789", "first_name" => "Jane" } ])
        end

        it "returns the unmasked SSN " do
          result = fetcher.fetch(
            account_id: account_id,
            cbv_flow_id: cbv_flow_id,
            client_agency_id: client_agency_id
          )
          expect(result).to eq("123-45-6789")
        end

        it "tracks an event with success = true" do
          fetcher.fetch(
            account_id: account_id,
            cbv_flow_id: cbv_flow_id,
            client_agency_id: client_agency_id
          )

          expect(event_logger).to have_received(:track).with(
            described_class::AUDIT_EVENT,
            nil,
            hash_including(
              cbv_flow_id: cbv_flow_id,
              client_agency_id: client_agency_id,
              aggregator_account_id: account_id,
              success: true
            )
          )
        end

        it "does not include the complete SSN in the audit event payload" do
          captured_payload = nil
          allow(event_logger).to receive(:track) do |_event, _user, payload|
            captured_payload = payload
          end

          fetcher.fetch(
            account_id: account_id,
            cbv_flow_id: cbv_flow_id,
            client_agency_id: client_agency_id
          )

          flattened = captured_payload.values.map(&:to_s).join(" ")
          expect(flattened).not_to include("123-45-6789")
          expect(flattened).not_to include("123456789")
        end
      end

      context "when Argyle returns an empty results array" do
        before do
          allow(argyle_service).to receive(:fetch_identities_api).and_return("results" => [])
        end

        it "returns nil" do
          expect(
            fetcher.fetch(
              account_id: account_id,
              cbv_flow_id: cbv_flow_id,
              client_agency_id: client_agency_id
            )
          ).to be_nil
        end

        it "tracks an event with success: false" do
          fetcher.fetch(
            account_id: account_id,
            cbv_flow_id: cbv_flow_id,
            client_agency_id: client_agency_id
          )

          expect(event_logger).to have_received(:track).with(
            described_class::AUDIT_EVENT,
            nil,
            hash_including(success: false)
          )
        end
      end

      context "when the first result has no ssn field" do
        before do
          allow(argyle_service).to receive(:fetch_identities_api)
            .and_return("results" => [ { "first_name" => "Jane" } ])
        end

        it "returns nil" do
          expect(
            fetcher.fetch(
              account_id: account_id,
              cbv_flow_id: cbv_flow_id,
              client_agency_id: client_agency_id
            )
          ).to be_nil
        end
      end

      context "when the result has a blank ssn" do
        before do
          allow(argyle_service).to receive(:fetch_identities_api)
            .and_return("results" => [ { "ssn" => "" } ])
        end

        it "returns nil" do
          expect(
            fetcher.fetch(
              account_id: account_id,
              cbv_flow_id: cbv_flow_id,
              client_agency_id: client_agency_id
            )
          ).to be_nil
        end
      end

      context "when the Argyle call raises" do
        let(:error) { Faraday::ConnectionFailed.new("argyle is down") }

        before do
          allow(argyle_service).to receive(:fetch_identities_api).and_raise(error)
          allow(NewRelic::Agent).to receive(:notice_error)
        end

        it "returns nil" do
          expect {
            @result = fetcher.fetch(
              account_id: account_id,
              cbv_flow_id: cbv_flow_id,
              client_agency_id: client_agency_id
            )
          }.not_to raise_error
          expect(@result).to be_nil
        end

        it "notices the error in NewRelic with custom params" do
          fetcher.fetch(
            account_id: account_id,
            cbv_flow_id: cbv_flow_id,
            client_agency_id: client_agency_id
          )

          expect(NewRelic::Agent).to have_received(:notice_error).with(
            error,
            custom_params: hash_including(
              cbv_flow_id: cbv_flow_id,
              client_agency_id: client_agency_id,
              aggregator_account_id: account_id
            )
          )
        end

        it "tracks an event with success: false and the error class" do
          fetcher.fetch(
            account_id: account_id,
            cbv_flow_id: cbv_flow_id,
            client_agency_id: client_agency_id
          )

          expect(event_logger).to have_received(:track).with(
            described_class::AUDIT_EVENT,
            nil,
            hash_including(success: false, error_class: "Faraday::ConnectionFailed")
          )
        end
      end

      context "when account_id is blank" do
        before do
          allow(argyle_service).to receive(:fetch_identities_api)
          allow(NewRelic::Agent).to receive(:notice_error)
        end

        it "returns nil" do
          expect {
            @result = fetcher.fetch(
              account_id: "",
              cbv_flow_id: cbv_flow_id,
              client_agency_id: client_agency_id
            )
          }.not_to raise_error
          expect(@result).to be_nil
        end

        it "notices the error in NewRelic with custom params" do
          fetcher.fetch(
            account_id: "",
            cbv_flow_id: cbv_flow_id,
            client_agency_id: client_agency_id
          )

          expect(NewRelic::Agent).to have_received(:notice_error).with(
            ArgumentError,
            custom_params: hash_including(
              cbv_flow_id: cbv_flow_id,
              client_agency_id: client_agency_id,
              aggregator_account_id: ""
            )
          )
        end

        it "tracks an event with success: false and the error class" do
          fetcher.fetch(
            account_id: "",
            cbv_flow_id: cbv_flow_id,
            client_agency_id: client_agency_id
          )

          expect(event_logger).to have_received(:track).with(
            described_class::AUDIT_EVENT,
            nil,
            hash_including(success: false, error_class: "ArgumentError")
          )
        end

        it "doesn't call Argyle" do
          fetcher.fetch(
            account_id: "",
            cbv_flow_id: cbv_flow_id,
            client_agency_id: client_agency_id
          )

          expect(argyle_service).not_to have_received(:fetch_identities_api)
        end
      end
    end
  end
