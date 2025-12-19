require 'rails_helper'

RSpec.describe MixpanelEventTracker do
  describe '.track' do
    let(:event_type) { 'TestEvent' }
    let(:request) { nil }
    let(:attributes) { { key: 'value' } }
    let(:tracker) { described_class.for_request(nil) }

    before do
      # Since we're stubbing this in spec_helper, make our tests in this file call original as well
      allow_any_instance_of(MixpanelEventTracker).to receive(:track).and_call_original
    end

    it 'calls Mixpanel::Tracker.track with correct parameters' do
      expect_any_instance_of(Mixpanel::Tracker).to receive(:track)
      tracker.track(event_type, request, attributes)
    end

    context 'when an error occurs' do
      before do
        allow_any_instance_of(Mixpanel::Tracker).to receive(:track).and_raise(StandardError.new('Test error'))
      end

      it 'logs an error message' do
        expect { tracker.track(event_type, request, attributes) }.to raise_exception(StandardError, 'Test error')
      end
    end

    context 'distinct_id formatting' do
      let(:people_double) { instance_double(Mixpanel::People) }

      before do
        allow_any_instance_of(Mixpanel::Tracker).to receive(:people).and_return(people_double)
        allow(people_double).to receive(:set)
      end

      context 'when MIXPANEL_DISTINCT_ID_PREFIX is set' do
        before do
          allow(ENV).to receive(:[]).and_call_original
          allow(ENV).to receive(:[]).with("MIXPANEL_DISTINCT_ID_PREFIX").and_return("developerA")
        end

        it 'prefixes the distinct_id for applicant events' do
          expect_any_instance_of(Mixpanel::Tracker).to receive(:track).with("developerA-applicant-123", event_type, anything)
          tracker.track(event_type, request, { cbv_applicant_id: "123" })
        end

        it 'prefixes the distinct_id for caseworker events' do
          expect_any_instance_of(Mixpanel::Tracker).to receive(:track).with("developerA-caseworker-456", event_type, anything)
          tracker.track(event_type, request, { user_id: "456" })
        end
      end

      context 'when MIXPANEL_DISTINCT_ID_PREFIX is not set' do
        before do
          allow(ENV).to receive(:[]).and_call_original
          allow(ENV).to receive(:[]).with("MIXPANEL_DISTINCT_ID_PREFIX").and_return(nil)
        end

        it 'does not prefix the distinct_id for applicant events' do
          expect_any_instance_of(Mixpanel::Tracker).to receive(:track).with("applicant-123", event_type, anything)
          tracker.track(event_type, request, { cbv_applicant_id: "123" })
        end

        it 'does not prefix the distinct_id for caseworker events' do
          expect_any_instance_of(Mixpanel::Tracker).to receive(:track).with("caseworker-456", event_type, anything)
          tracker.track(event_type, request, { user_id: "456" })
        end
      end
    end
  end
end
