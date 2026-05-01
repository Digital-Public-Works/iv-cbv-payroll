require 'rails_helper'

RSpec.describe Api::UserEventsController, type: :controller do
  describe "POST #user_action" do
    let(:cbv_flow) { create :cbv_flow }
    let(:valid_params) do
      {
        events: {
            event_name: "ApplicantOpenedHelpModal",
            attributes: event_attributes
        }
      }
    end
    let(:invalid_params) do
      {
        events: {
            event_name: "InvalidEvent",
            attributes: event_attributes
        }
      }
    end

    before do
      session[:cbv_flow_id] = cbv_flow.id
    end

    context "when tracking a valid event" do
      let(:event_attributes) do
        {
          source: "banner"
        }
      end

      it "tracks an event with Mixpanel" do
        expect(MixpanelEventTrackingJob).to receive(:perform_later).with("ApplicantOpenedHelpModal", anything, hash_including(
          time: be_a(Integer),
          source: "banner",
          cbv_flow_id: cbv_flow.id
        ))
        post :user_action, params: valid_params
      end

      it "returns a success response" do
        post :user_action, params: valid_params
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to eq({ "status" => "ok" })
      end
    end

    context "when tracking an invalid event" do
      let(:event_attributes) do
        {
          source: "banner"
        }
      end

      it "returns an error response in production" do
        allow(Rails.env).to receive(:production?).and_return(true)
        post :user_action, params: invalid_params
        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)).to eq({ "status" => "error" })
      end

      it "raises an error in non-production" do
        allow(Rails.env).to receive(:production?).and_return(false)
        expect {
          post :user_action, params: invalid_params
        }.to raise_error('Unknown Event Type "InvalidEvent"')
      end
    end
  end
  describe "#user_action" do
    let(:cbv_flow) { create :cbv_flow }
    let(:valid_params) do
      { events: { event_name: event_name, attributes: event_attributes } }
    end

    before do
      session[:cbv_flow_id] = cbv_flow.id
    end

    context "when tracking a ApplicantSelectedEmployerOrPlatformItem event" do
      let(:event_name) { "ApplicantSelectedEmployerOrPlatformItem" }

      context "when selecting the payroll providers tab" do
        let(:event_attributes) do
          {
            item_type: "platform",
            item_id: 123,
            item_name: "Test Payroll Provider",
            locale: "en",
            is_default_option: "true"
          }
        end

        it "tracks an event with Mixpanel (with selected_tab = platform)" do
          expect(MixpanelEventTrackingJob).to receive(:perform_later).with("ApplicantSelectedEmployerOrPlatformItem", anything, hash_including(
            time: be_a(Integer),
            cbv_flow_id: cbv_flow.id,
            invitation_id: cbv_flow.cbv_flow_invitation_id,
            item_type: "platform",
            item_id: "123",
            item_name: "Test Payroll Provider",
            is_default_option: "true",
            locale: "en"
          ))
          post :user_action, params: valid_params
        end
      end

      context "when selecting the common employers tab" do
        let(:event_attributes) do
          {
            item_type: "employer",
            item_id: 123,
            item_name: "Test Employer",
            locale: "en",
            is_default_option: "true"
          }
        end

        it "tracks an event with Mixpanel (with selected_tab = employer)" do
          expect(MixpanelEventTrackingJob).to receive(:perform_later).with("ApplicantSelectedEmployerOrPlatformItem", anything, hash_including(
            time: be_a(Integer),
            cbv_flow_id: cbv_flow.id,
            invitation_id: cbv_flow.cbv_flow_invitation_id,
            item_type: "employer",
            item_id: "123",
            item_name: "Test Employer",
            is_default_option: "true",
            locale: "en"
          ))
          post :user_action, params: valid_params
        end
      end
    end

    context "when tracking a PinwheelShowLoginPage event" do
      let(:event_name) { "ApplicantViewedPinwheelLoginPage" }
      let(:event_attributes) do
        {
          screen_name: "LOGIN",
          employer_name: "Bob's Burgers",
          platform_name: "Test Payroll Platform Name",
          locale: "en"
        }
      end

      it "tracks an event with Mixpanel" do
        expect(MixpanelEventTrackingJob).to receive(:perform_later).with("ApplicantViewedPinwheelLoginPage", anything, hash_including(
          time: be_a(Integer),
          cbv_flow_id: cbv_flow.id,
          invitation_id: cbv_flow.cbv_flow_invitation_id,
          locale: "en",
          screen_name: "LOGIN",
          employer_name: "Bob's Burgers",
          platform_name: "Test Payroll Platform Name"
        ))
        post :user_action, params: valid_params
      end
    end

    context "when tracking a UserManuallySwitchedLanguage event" do
      let(:event_name) { "ApplicantManuallySwitchedLanguage" }
      let(:event_attributes) do
        {
          locale: "es"
        }
      end

      it "tracks an event with Mixpanel" do
        expect(MixpanelEventTrackingJob).to receive(:perform_later).with("ApplicantManuallySwitchedLanguage", anything, hash_including(
          time: be_a(Integer),
          cbv_flow_id: cbv_flow.id,
          invitation_id: cbv_flow.cbv_flow_invitation_id,
          locale: "es"
        ))
        post :user_action, params: valid_params
      end
    end

    context "when tracking a ApplicantConsentedToTerms event" do
      let(:event_name) { "ApplicantConsentedToTerms" }
      let(:event_attributes) { {} }

      it "tracks an event with Mixpanel" do
        expect(MixpanelEventTrackingJob).to receive(:perform_later).with("ApplicantConsentedToTerms", anything, hash_including(
          time: be_a(Integer),
          cbv_flow_id: cbv_flow.id,
          invitation_id: cbv_flow.cbv_flow_invitation_id
        ))
        post :user_action, params: valid_params
      end
    end

    context "when tracking an ApplicantRemovedArgyleAccount event" do
      let(:event_name) { "ApplicantRemovedArgyleAccount" }
      let(:aggregator_account_id) { "argyle-account-to-remove" }

      let!(:payroll_account) do
        create(:payroll_account, :argyle, cbv_flow: cbv_flow, aggregator_account_id: aggregator_account_id)
      end

      let(:event_attributes) do
        # namespaceTrackingProperties on the JavaScript side prefixes with "argyle."
        { "argyle.accountId" => aggregator_account_id, "argyle.userId" => "some-user" }
      end

      it "soft-deletes the payroll_account for the removed Argyle account" do
        expect {
          post :user_action, params: valid_params
        }.to change { PayrollAccount.with_discarded.find(payroll_account.id).discarded? }.from(false).to(true)

        expect(response).to have_http_status(:ok)
      end

      it "does not discard a payroll_account belonging to a different cbv_flow" do
        other_flow = create(:cbv_flow)
        other_account = create(:payroll_account, :argyle, cbv_flow: other_flow, aggregator_account_id: aggregator_account_id)

        post :user_action, params: valid_params

        expect(PayrollAccount.with_discarded.find(payroll_account.id).discarded?).to be true
        expect(PayrollAccount.with_discarded.find(other_account.id).discarded?).to be false
      end

      it "still tracks the analytics event even if discard fails" do
        allow_any_instance_of(CbvFlow).to receive(:payroll_accounts).and_raise(StandardError, "crashme")

        expect(MixpanelEventTrackingJob).to receive(:perform_later).with(
          "ApplicantRemovedArgyleAccount", anything, hash_including("argyle.accountId" => aggregator_account_id)
        )
        expect(Rails.logger).to receive(:error).with(/Unable to discard payroll_account/)

        post :user_action, params: valid_params

        expect(response).to have_http_status(:ok)
      end

      context "when session has no cbv_flow" do
        before { session[:cbv_flow_id] = nil }

        it "does not raise and does not discard anything" do
          post :user_action, params: valid_params

          expect(response).to have_http_status(:ok)
          expect(PayrollAccount.with_discarded.find(payroll_account.id).discarded?).to be false
        end
      end

      context "when argyle.accountId is missing from attributes" do
        let(:event_attributes) { { "argyle.userId" => "some-user" } }

        it "does not raise and does not discard" do
          post :user_action, params: valid_params

          expect(response).to have_http_status(:ok)
          expect(PayrollAccount.with_discarded.find(payroll_account.id).discarded?).to be false
        end
      end
    end

    context "when tracking a ApplicantViewedHelpText event" do
      let(:event_name) { "ApplicantViewedHelpText" }

      context "for 'who is this for' section" do
        let(:event_attributes) do
          {
            section: "who_is_this_tool_for"
          }
        end

        it "tracks an event with Mixpanel" do
          expect(MixpanelEventTrackingJob).to receive(:perform_later).with("ApplicantViewedHelpText", anything, hash_including(
            time: be_a(Integer),
            cbv_flow_id: cbv_flow.id,
            invitation_id: cbv_flow.cbv_flow_invitation_id,
            section: "who_is_this_tool_for"
          ))
          post :user_action, params: valid_params
        end
      end

      context "for 'what if I cant use this' section" do
        let(:event_attributes) do
          {
            section: "what_if_i_cant_use_this_tool"
          }
        end

        it "tracks an event with Mixpanel" do
          expect(MixpanelEventTrackingJob).to receive(:perform_later).with("ApplicantViewedHelpText", anything, hash_including(
            time: be_a(Integer),
            cbv_flow_id: cbv_flow.id,
            invitation_id: cbv_flow.cbv_flow_invitation_id,
            section: "what_if_i_cant_use_this_tool"
          ))
          post :user_action, params: valid_params
        end
      end
    end
  end
end
