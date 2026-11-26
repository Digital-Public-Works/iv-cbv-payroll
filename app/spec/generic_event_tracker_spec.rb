# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GenericEventTracker do
  let(:browser_user_agent) { "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36" }

  describe '#track' do
    around do |example|
      ClimateControl.modify ACTIVEJOB_ENABLED: 'true' do
        example.run
      end
    end

    it 'populates default attributes' do
      expect(MixpanelEventTrackingJob).to receive(:perform_later).with("myEvent", anything, hash_including(
        time: an_instance_of(Integer),
        cbv_flow_id: "cbv_flow_id",
        locale: an_instance_of(String),
        user_agent: browser_user_agent,
        client_agency_id: "client_agency_id",
        ip: "ip"
      ))
      request_mock = instance_double(ActionDispatch::Request, params: { "client_agency_id" => "client_agency_id" }, session: { cbv_flow_id: "cbv_flow_id" }, remote_ip: "ip", headers: { "User-Agent" => browser_user_agent })
      described_class.new.track("myEvent", request_mock, {})
    end

    context 'filtering traffic that is not from applicants' do
      def request_with_user_agent(user_agent)
        instance_double(ActionDispatch::Request, params: {}, session: {}, remote_ip: "ip", headers: { "User-Agent" => user_agent })
      end

      before { allow(MixpanelEventTrackingJob).to receive(:perform_later) }

      it 'does not track requests from the k6 load-test client' do
        described_class.new.track("myEvent", request_with_user_agent("Grafana k6/1.4.0 (https://k6.io/)"), {})

        expect(MixpanelEventTrackingJob).not_to have_received(:perform_later)
      end

      it 'does not track events for load-test flows, even without a request' do
        load_test_device_id = Api::LoadTestSessionsController::LOAD_TEST_DEVICE_ID
        described_class.new.track("myEvent", nil, { device_id: load_test_device_id })
        described_class.new.track("myEvent", nil, { "device_id" => load_test_device_id })

        expect(MixpanelEventTrackingJob).not_to have_received(:perform_later)
      end

      it 'does not track requests from bots' do
        described_class.new.track("myEvent", request_with_user_agent("Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"), {})

        expect(MixpanelEventTrackingJob).not_to have_received(:perform_later)
      end

      [
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36",
        "ReactorNetty/1.3.7", # Argyle webhooks
        nil
      ].each do |user_agent|
        it "tracks requests with User-Agent #{user_agent.inspect}" do
          described_class.new.track("myEvent", request_with_user_agent(user_agent), {})

          expect(MixpanelEventTrackingJob).to have_received(:perform_later).with("myEvent", anything, anything)
        end
      end

      it 'tracks events without a request for real flows' do
        described_class.new.track("myEvent", nil, { device_id: "real-device" })

        expect(MixpanelEventTrackingJob).to have_received(:perform_later).with("myEvent", nil, anything)
      end
    end

    context 'raises an error' do
      let(:request_mock) { instance_double(ActionDispatch::Request, params: { "client_agency_id" => "client_agency_id" }, session: { cbv_flow_id: "cbv_flow_id" }, remote_ip: "ip", headers: { "User-Agent" => browser_user_agent }) }
      let(:event_type) { "myEvent" }

      before do
        allow(MixpanelEventTrackingJob).to receive(:perform_later).and_raise(RuntimeError)
        allow(Rails.logger).to receive(:error)
        allow(Rails.env).to receive(:production?).and_return(false)
      end

      it 'logs to error with that event and reraises an error in non prod environments' do
        expect { described_class.new.track(event_type, request_mock, {}) }
          .to raise_error(RuntimeError)
        expect(Rails.logger).to have_received(:error)
          .with(/Unable to track event \(#{event_type}\): RuntimeError, line: /)
          .with(/line: /)
          .with(/.rb:/)
      end

      it 'logs an error but does not raise in prod' do
        allow(Rails.env).to receive(:production?).and_return(true)

        request_mock = instance_double(ActionDispatch::Request, params: { "client_agency_id" => "client_agency_id" }, session: { cbv_flow_id: "cbv_flow_id" }, remote_ip: "ip", headers: { "User-Agent" => browser_user_agent })
        expect { described_class.new.track(event_type, request_mock, {}) }
          .not_to raise_error
        expect(Rails.logger).to have_received(:error).with(/Unable to track event \(#{event_type}\): RuntimeError/)
      end
    end
  end
end
