require 'rails_helper'

RSpec.describe Cbv::SessionsController, type: :controller do
  include ActiveSupport::Testing::TimeHelpers

  describe "POST #refresh" do
    it "refuses a stale tab's Extend, so it can't announce its old flow" do
      session[:cbv_flow_id] = create(:cbv_flow, :invited).id
      request.headers[CbvFlowTabBinding::TAB_FLOW_HEADER] = "0"
      request.headers["Accept"] = "text/vnd.turbo-stream.html, text/html"

      post :refresh

      # not 2xx: the Extend form submission must report failure
      expect(response).to have_http_status(:conflict)
      expect(response.body).to include(%(action="redirect"))
      expect(session[:last_seen]).to be_nil
    end

    it "extends as before when the session has already expired (no flow to be stale against)" do
      request.headers[CbvFlowTabBinding::TAB_FLOW_HEADER] = "123"

      post :refresh

      expect(response).to have_http_status(:ok)
    end

    it "stores the current time in session[:last_seen] and returns ok" do
      freeze_time do
        post :refresh

        expect(session[:last_seen]).to eq(Time.current.to_i)
        expect(response).to have_http_status(:ok)
        expect(response.body).to be_blank
      end
    end
  end

  describe 'GET #end' do
    before do
      session[:cbv_flow_id] = create(:cbv_flow, :invited).id
    end

    context 'when timeout is true' do
      it 'records the timeout, with the flow, when it ends the session' do
        flow = CbvFlow.find(session[:cbv_flow_id])
        expect_any_instance_of(GenericEventTracker).to receive(:track).with(
          TrackEvent::ApplicantTimedOut, anything,
          hash_including(cbv_flow_id: flow.id, client_agency_id: "sandbox", invitation_id: flow.cbv_flow_invitation_id)
        )

        get :end, params: { timeout: 'true' }
      end

      it 'keeps the language on the timeout page' do
        get :end, params: { timeout: 'true', locale: 'es' }

        expect(response).to redirect_to(cbv_flow_session_timeout_path(client_agency_id: "sandbox", locale: "es"))
      end

      it 'clears session and sets a notice without tracking timeout event' do
        get :end, params: { timeout: 'true' }
        expect(session[:cbv_flow_id]).to be_nil
      end

      it 'redirects to session timeout page with agency' do
        get :end, params: { timeout: 'true' }
        expect(response).to redirect_to(cbv_flow_session_timeout_path(client_agency_id: "sandbox", locale: "en"))
      end
    end

    context 'when timeout is not true' do
      it 'clears session without tracking timeout event' do
        expect(controller).not_to receive(:track_timeout_event)
        get :end
        expect(session[:cbv_flow_id]).to be_nil
      end
    end

    # Every tab runs its own timer, but the session is shared: an idle tab
    # running out must not end a session another tab is using.
    context 'when another tab was active recently' do
      it 'keeps the session and tells this tab it is open in another tab' do
        session[:last_seen] = 10.minutes.ago.to_i

        get :end, params: { timeout: 'true' }

        expect(session[:cbv_flow_id]).to be_present
        expect(response).to redirect_to(cbv_flow_session_switched_path(reason: "open_elsewhere", locale: "en"))
      end

      it "doesn't record a timeout when it keeps the session" do
        session[:last_seen] = 10.minutes.ago.to_i
        expect_any_instance_of(GenericEventTracker).not_to receive(:track)

        get :end, params: { timeout: 'true' }
      end

      it "keeps the page's language" do
        session[:last_seen] = 10.minutes.ago.to_i

        get :end, params: { timeout: 'true', locale: 'es' }

        expect(response).to redirect_to(cbv_flow_session_switched_path(reason: "open_elsewhere", locale: "es"))
      end

      it 'still ends a session idle for the whole timeout, allowing for the timer starting late' do
        session[:last_seen] = (Rails.application.config.cbv_session_expires_after - 30.seconds).ago.to_i

        get :end, params: { timeout: 'true' }

        expect(session[:cbv_flow_id]).to be_nil
        expect(response).to redirect_to(cbv_flow_session_timeout_path(client_agency_id: "sandbox", locale: "en"))
      end

      it 'still ends the session when the applicant clicks "End session", without recording a timeout' do
        session[:last_seen] = 26.minutes.ago.to_i
        expect_any_instance_of(GenericEventTracker).not_to receive(:track)

        get :end

        expect(session[:cbv_flow_id]).to be_nil
      end

      it 'ends a session with no recorded activity, as before' do
        session.delete(:last_seen)

        get :end, params: { timeout: 'true' }

        expect(session[:cbv_flow_id]).to be_nil
      end
    end

    context 'when flow is missing' do
      it 'redirects to root with timeout flag' do
        session[:cbv_flow_id] = nil

        get :end

        expect(response).to redirect_to(root_url(cbv_flow_timeout: true, locale: "en"))
      end
    end
  end

  describe 'GET #switched' do
    render_views

    it 'explains the page was replaced by another report' do
      get :switched

      expect(response.body).to include(I18n.t("cbv.sessions.switched.title"))
    end

    it 'explains the session is open in another tab after an idle timeout' do
      get :switched, params: { reason: "open_elsewhere" }

      expect(response.body).to include(I18n.t("cbv.sessions.switched.open_elsewhere.title"))
      expect(response.body).not_to include(I18n.t("cbv.sessions.switched.title"))
    end

    it "brands the header with the partner of the report the browser now holds" do
      session[:cbv_flow_id] = create(:cbv_flow, :invited, client_agency_id: "sandbox").id

      get :switched

      expect(response.body).to include(I18n.t("shared.header.cbv_flow_title.sandbox"))
    end

    it "has no session timeout warning, whose Extend or End would act on the other tab's flow" do
      session[:cbv_flow_id] = create(:cbv_flow, :invited).id

      get :switched

      expect(response.body).not_to include("session-timeout-modal")
    end

    it "falls back to the domain's partner when the session holds no report" do
      allow(controller).to receive(:detect_client_agency_from_domain).and_return("sandbox")

      get :switched

      expect(response.body).to include(I18n.t("shared.header.cbv_flow_title.sandbox"))
    end
  end

  describe 'GET #timeout' do
    context 'you come to the timeout page with a session' do
      before do
        session[:cbv_flow_id] = create(:cbv_flow, :invited).id
      end

      it 'removes the session' do
        get :timeout
        expect(session[:cbv_flow_id]).to be_nil
      end
    end

    context 'with a valid client_agency_id' do
      it 'renders the timeout page' do
        get :timeout, params: { client_agency_id: 'sandbox' }
        expect(response).to have_http_status(:ok)
      end
    end

    context 'without a valid client_agency_id' do
      it 'redirects to root with cbv_flow_timeout flag' do
        get :timeout, params: { client_agency_id: 'invalid_agency' }
        expect(response).to redirect_to(root_url(cbv_flow_timeout: true))
      end

      it 'redirects to root when client_agency_id is missing' do
        get :timeout
        expect(response).to redirect_to(root_url(cbv_flow_timeout: true))
      end
    end
  end
end
