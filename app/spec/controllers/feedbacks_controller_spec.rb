require "rails_helper"

RSpec.describe FeedbacksController, type: :controller do
  describe "GET #show" do
    let(:event_logger) { instance_double(GenericEventTracker) }
    let(:feedback_form_url) { ApplicationHelper::APPLICANT_FEEDBACK_FORM }
    let(:cbv_flow) { create(:cbv_flow, :invited) }

    before do
      session[:cbv_flow_id] = cbv_flow.id
      allow(controller).to receive(:event_logger).and_return(event_logger)
      allow(event_logger).to receive(:track)
      allow(ApplicationController.helpers).to receive(:feedback_form_url).and_return(feedback_form_url)
    end

    it "redirects to the feedback form and tracks the event with source" do
      referer_url = cbv_flow_employer_search_path(locale: :en)
      get :show, params: { referer: referer_url }

      expect(event_logger).to have_received(:track).with(
        "ApplicantClickedFeedbackLink",
        kind_of(ActionDispatch::Request),
        hash_including(
          referer: referer_url,
          client_agency_id: cbv_flow.client_agency_id,
          cbv_flow_id: cbv_flow.id
        )
      )
      expect(response).to have_http_status(:redirect)
      expect(response.location).to start_with(ApplicationController.helpers.feedback_form_url)
    end

    it "redirects to the survey form and tracks the event with source" do
      get :show, params: { form: "survey" }

      expect(event_logger).to have_received(:track).with(
        "ApplicantClickedFeedbackSurveyLink",
        kind_of(ActionDispatch::Request),
        hash_including(
          client_agency_id: cbv_flow.client_agency_id,
          cbv_flow_id: cbv_flow.id
        )
      )
      expect(response).to have_http_status(:redirect)
      expect(response.location).to start_with(ApplicationController.helpers.survey_form_url)
    end

    it "appends params to form URL based on locale" do
      get :show, params: { locale: :es }
      expect(response.location).to include(ERB::Util.url_encode("Español"))
    end

    it "appends params to form URL based on agency" do
      cbv_flow.update(client_agency_id: "az_des")

      get :show
      expect(response.location).to include(ERB::Util.url_encode("Arizona"))
    end
  end
end
