require "rails_helper"

RSpec.describe Cbv::EmployerSearchesController do
  include PinwheelApiHelper
  include ArgyleApiHelper

  describe "#show" do
    let(:cbv_flow) { create(:cbv_flow, :invited) }
    let(:pinwheel_token_id) { "abc-def-ghi" }
    let(:user_token) { "foobar" }


    before do
      session[:cbv_flow_id] = cbv_flow.id
    end

    context "when rendering views" do
      render_views

      it "renders properly" do
        get :show
        expect(response).to be_successful
      end

      it "tracks an event" do
        allow(MixpanelEventTrackingJob).to receive(:perform_later).with("CbvPageView", anything, anything)
        expect(MixpanelEventTrackingJob).to receive(:perform_later).with("ApplicantAccessedSearchPage", anything, hash_including(
          time: be_a(Integer),
          cbv_applicant_id: cbv_flow.cbv_applicant_id,
          cbv_flow_id: cbv_flow.id,
          invitation_id: cbv_flow.cbv_flow_invitation_id
        ))
        get :show
      end

      it "tracks event when clicking popular payroll providers" do
        allow(MixpanelEventTrackingJob).to receive(:perform_later).with("CbvPageView", anything, anything)
        expect(MixpanelEventTrackingJob).to receive(:perform_later).with("ApplicantClickedPopularPayrollProviders", anything, hash_including(
            time: be_a(Integer),
            cbv_applicant_id: cbv_flow.cbv_applicant_id,
            cbv_flow_id: cbv_flow.id,
            invitation_id: cbv_flow.cbv_flow_invitation_id
          ))
        allow(MixpanelEventTrackingJob).to receive(:perform_later).with("ApplicantAccessedSearchPage", anything, anything)
        get :show, params: { type: "payroll" }
      end

      it "tracks a Mixpanel event when clicking popular app employers" do
        allow(MixpanelEventTrackingJob).to receive(:perform_later).with("CbvPageView", anything, anything)
        expect(MixpanelEventTrackingJob).to receive(:perform_later).with("ApplicantClickedPopularAppEmployers", anything, hash_including(
          time: be_a(Integer),
          cbv_applicant_id: cbv_flow.cbv_applicant_id,
          cbv_flow_id: cbv_flow.id,
          invitation_id: cbv_flow.cbv_flow_invitation_id
        ))
        allow(MixpanelEventTrackingJob).to receive(:perform_later).with("ApplicantAccessedSearchPage", anything, anything)
        get :show, params: { type: "employer" }
      end

      it "renders the expandable unemployed tips box with tracking attributes" do
        get :show

        html = Capybara.string(response.body)
        expect(html).to have_css("div[data-controller~='unemployed-tips'][data-controller~='click-tracker']")
        expect(html).to have_css("#unemployed-tips-section")

        tips_button = html.find("button[data-element-name='unemployed_tips_help']")
        expect(tips_button.text).to include("I am currently unemployed")
        expect(tips_button["data-action"]).to include("click->click-tracker#track")
        expect(tips_button["data-track-event"]).to eq("ApplicantAccessedUnemployedHelp")

        close_link = html.find("[data-element-name='close_unemployed_tips']", visible: false)
        expect(close_link.text).to include("Close this message")
        expect(close_link["data-track-event"]).to eq("ApplicantClosedUnemployedHelp")
      end
    end

    context "when user searches for an unemployment-related term" do
      before do
        argyle_stub_request_employer_search_response('bob')
      end

      render_views

      it "renders the unemployment search tips alert" do
        get :show, params: { query: "unemployed" }
        expect(response).to be_successful
        expect(response.body).to include("Are you unemployed?")
        expect(response.body).to include("Go back to search")
      end

      it "still renders search results below the tips" do
        get :show, params: { query: "unemployed" }
        expect(response).to be_successful
        expect(response.body).to include("Results")
      end

      it "tracks ApplicantAccessedUnemployedHelp with search source" do
        allow(MixpanelEventTrackingJob).to receive(:perform_later).with("CbvPageView", anything, anything)
        allow(MixpanelEventTrackingJob).to receive(:perform_later).with("ApplicantSearchedForEmployer", anything, anything)
        expect(MixpanelEventTrackingJob).to receive(:perform_later).with(
          "ApplicantAccessedUnemployedHelp", anything, hash_including(
            cbv_applicant_id: cbv_flow.cbv_applicant_id,
            cbv_flow_id: cbv_flow.id,
            invitation_id: cbv_flow.cbv_flow_invitation_id,
            unemployed_tips_source: "search"
          )
        )
        get :show, params: { query: "unemployed" }
      end

      it "renders the go back link with correct tracking attributes" do
        get :show, params: { query: "fired" }

        html = Capybara.string(response.body)
        go_back_link = html.find("[data-element-name='go_back_to_search_from_unemployment_tips']")
        expect(go_back_link["data-track-event"]).to eq("ApplicantClosedUnemployedHelp")
        expect(go_back_link["data-context-unemployed-tips-source"]).to eq("search")
      end

      it "matches Spanish terms" do
        get :show, params: { query: "Despedido" }
        expect(response).to be_successful
        expect(response.body).to include("Are you unemployed?")
      end
    end

    context "when user searches for a non-unemployment term" do
      before do
        argyle_stub_request_employer_search_response('bob')
      end

      render_views

      it "does not render the unemployment search tips" do
        get :show, params: { query: "walmart" }
        expect(response).to be_successful
        expect(response.body).not_to include("Are you unemployed?")
      end
    end

    context "when there are no employer search results" do
      before do
        argyle_stub_request_employer_search_response('bob')
      end

      render_views

      it "renders the help section with a link to missing results page" do
        get :show, params: { query: "no_results" }
        expect(response).to be_successful
        expect(response.body).to include("Trouble finding your employer or payroll provider?")
        expect(response.body).to include("Explore your options")
        expect(response.body).to include(cbv_flow_missing_results_path)
      end
    end

    context "when there are search results" do
      before do
        argyle_stub_request_employer_search_response('bob')
      end

      render_views

      it "renders successfully" do
        get :show, params: { query: "results" }
        expect(response).to be_successful
      end

      it "tracks a Mixpanel event" do
        allow(MixpanelEventTrackingJob).to receive(:perform_later).with("CbvPageView", anything, anything)
        expect(MixpanelEventTrackingJob).to receive(:perform_later).with(
          "ApplicantSearchedForEmployer", anything, hash_including(
          cbv_applicant_id: cbv_flow.cbv_applicant_id,
          cbv_flow_id: cbv_flow.id,
          invitation_id: cbv_flow.cbv_flow_invitation_id,
          num_results: 5,
          has_payroll_account: false,
          pinwheel_result_count: 0,
          argyle_result_count: 5
        ))
        get :show, params: { query: "results" }
      end

      context "when some results should be blocked" do
        before do
          argyle_stub_request_employer_search_response('bob')
          stub_const("ProviderSearchService::BLOCKED_ARGYLE_EMPLOYERS", [ "item_000017502" ])
        end

        render_views

        it "renders successfully without those results" do
          get :show, params: { query: "results" }
          expect(response).to be_successful
          expect(response.body).not_to include("Greens Group")
          expect(response.body).to include("Mr Greens")
        end
      end

      context "when the user enters a mixed-case query" do
        it "sends the query content to mixpanel as lowercase" do
          allow(MixpanelEventTrackingJob).to receive(:perform_later).with("CbvPageView", anything, anything)

          expect(MixpanelEventTrackingJob).to receive(:perform_later).with(
            "ApplicantSearchedForEmployer",
            anything,
            hash_including(
              query: "results"
            )
          )

          get :show, params: { query: "ReSuLtS" }
        end
      end
    end
  end
end
