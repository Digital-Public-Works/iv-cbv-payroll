require "rails_helper"

RSpec.describe Cbv::OtherJobsController do
  let(:cbv_flow) { create(:cbv_flow, :invited) }

  before do
    session[:cbv_flow_id] = cbv_flow.id
  end

  describe "#show" do
    render_views

    it "renders" do
      get :show
      expect(response).to be_successful
    end

    it "labels the radio group with the question and leaves it valid" do
      get :show
      expect(response.body).to have_css('fieldset.usa-fieldset[aria-labelledby="other-jobs-question"] input[type="radio"]', count: 2)
      expect(response.body).to have_css("#other-jobs-question")
      expect(response.body).not_to have_css('input[aria-invalid]')
    end

    context "after submitting without an answer" do
      it "links the radios to the error alert" do
        get :show, flash: { slim_alert: { "message" => I18n.t("shared.next_path.notice_no_answer"), "type" => "error", "field" => "has_other_jobs" } }

        expect(response.body).to have_css("div.usa-alert#slim-alert", text: I18n.t("shared.next_path.notice_no_answer"))
        expect(response.body).to have_css('input[type="radio"][aria-invalid="true"][aria-describedby="slim-alert"]', count: 2)
        expect(response.body).to have_css('fieldset[data-controller="field-error-focus"][data-field-error-focus-alert-id-value="slim-alert"]')
      end
    end
  end

  describe "#update" do
    it 'redirects when has_other_jobs is true' do
      patch :update, params: { cbv_flow: { has_other_jobs: 'true' } }
      expect(response).to redirect_to(cbv_flow_applicant_information_path)
    end

    it 'redirects when has_other_jobs is false' do
      patch :update, params: { cbv_flow: { has_other_jobs: 'false' } }
      expect(response).to redirect_to(cbv_flow_applicant_information_path)
    end

    it 'redirects with notice when no radio button has been selected' do
      patch :update, params: { cbv_flow: { has_other_jobs: '' } }
      expect(flash[:slim_alert]).to include(type: "error", field: "has_other_jobs")
      expect(response).to redirect_to(cbv_flow_other_job_path)
    end

    it 'tracks an event when has_other_jobs is true' do
      allow(MixpanelEventTrackingJob).to receive(:perform_later).with("CbvPageView", anything, anything)

      expect(MixpanelEventTrackingJob).to receive(:perform_later).with("ApplicantContinuedFromOtherJobsPage", anything, hash_including(
        time: be_a(Integer),
        cbv_flow_id: cbv_flow.id,
        client_agency_id: cbv_flow.client_agency_id,
        has_other_jobs: true
      ))
      patch :update, params: { cbv_flow: { has_other_jobs: 'true' } }
    end

    it 'tracks an event when has_other_jobs is false' do
      allow(MixpanelEventTrackingJob).to receive(:perform_later).with("CbvPageView", anything, anything)

      expect(MixpanelEventTrackingJob).to receive(:perform_later).with("ApplicantContinuedFromOtherJobsPage", anything, hash_including(
        time: be_a(Integer),
        cbv_flow_id: cbv_flow.id,
        client_agency_id: cbv_flow.client_agency_id,
        has_other_jobs: false
      ))
      patch :update, params: { cbv_flow: { has_other_jobs: 'false' } }
    end

    it 'does not track ApplicantContinuedFromOtherJobsPage event when no radio button is selected' do
      allow(MixpanelEventTrackingJob).to receive(:perform_later).with("CbvPageView", anything, anything)

      expect(MixpanelEventTrackingJob).not_to receive(:perform_later).with("ApplicantContinuedFromOtherJobsPage", anything, anything)
      patch :update, params: { cbv_flow: { has_other_jobs: '' } }
    end

    context "when event tracking fails in production" do
      before do
        allow(Rails.env).to receive(:production?).and_return(true)
        allow(Rails.logger).to receive(:error)
        allow(MixpanelEventTrackingJob).to receive(:perform_later).with("CbvPageView", anything, anything)
      end

      it 'continues when event tracking raises an exception' do
        allow(MixpanelEventTrackingJob).to receive(:perform_later).with("ApplicantContinuedFromOtherJobsPage", anything, anything).and_raise(StandardError)

        patch :update, params: { cbv_flow: { has_other_jobs: 'true' } }
        expect(response).to redirect_to(cbv_flow_applicant_information_path)
      end
    end
  end
end
