require 'rails_helper'

RSpec.describe Cbv::SessionsController, type: :controller do
  include ActiveSupport::Testing::TimeHelpers

  describe "POST #refresh" do
    it "stores the current time in session[:last_seen] and returns ok" do
      freeze_time do
        post :refresh

        expect(session[:last_seen]).to be_within(1.second).of(Time.current)
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
      it 'clears session and sets a notice without tracking timeout event' do
        get :end, params: { timeout: 'true' }
        expect(session[:cbv_flow_id]).to be_nil
      end

      it 'redirects to session timeout page with agency' do
        get :end, params: { timeout: 'true' }
        expect(response).to redirect_to(cbv_flow_session_timeout_path(client_agency_id: "sandbox"))
      end
    end

    context 'when timeout is not true' do
      it 'clears session without tracking timeout event' do
        expect(controller).not_to receive(:track_timeout_event)
        get :end
        expect(session[:cbv_flow_id]).to be_nil
      end
    end

    context 'when flow is missing' do
      it 'redirects to root with timeout flag' do
        session[:cbv_flow_id] = nil

        get :end

        expect(response).to redirect_to(root_url(cbv_flow_timeout: true))
      end
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
  end
end
