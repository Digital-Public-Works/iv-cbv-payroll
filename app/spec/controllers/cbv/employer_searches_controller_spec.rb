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

      it "shows the search prompt as the page header on initial load (no query)" do
        get :show

        html = Capybara.string(response.body)
        expect(html.find("#employer-search-h1").text.strip).to eq("Find your employer or payroll company")
        expect(html).to have_no_css("#employer-search-h1", text: "Search results")
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

      context "popular provider buttons" do
        let(:button_selector) { "#popular_providers_panel button[data-cbv-employer-search-target='employerButton']" }

        %w[payroll employer].each do |type|
          it "describes each popular #{type} option by its position out of the total" do
            get :show, params: { type: type }

            html = Capybara.string(response.body)
            buttons = html.all(button_selector)
            expect(buttons).not_to be_empty
            expect(html.find("#providers_total")).to have_text(buttons.size.to_s, exact: true)

            buttons.each_with_index do |button, index|
              position_id, total_id = button["aria-describedby"].split
              expect(total_id).to eq("providers_total")
              expect(html.find("##{position_id}")).to have_text("#{index + 1} of", exact: true)
            end
          end

          it "hides the #{type} position and total text from everyone except aria-describedby" do
            get :show, params: { type: type }

            html = Capybara.string(response.body)
            spans = html.all("#providers_total, [id^='providers_position_']")
            expect(spans.size).to eq(html.all(button_selector).size + 1)
            spans.each do |span|
              expect(span[:class].split).to include("display-none")
              expect(span[:class].split).not_to include("usa-sr-only")
            end
          end

          it "names each popular #{type} button by its visible provider name, stacked under the logo" do
            get :show, params: { type: type }

            Capybara.string(response.body).all(button_selector).each do |button|
              expect(button["aria-label"]).to be_nil
              expect(button.find("> span.display-block > img")["alt"]).to eq("")
              expect(button.find("> span.display-block > span.display-block.margin-top-1"))
                .to have_text(button["data-name"], exact: true)
            end
          end
        end

        it "translates the position text" do
          get :show, params: { type: "payroll", locale: :es }

          html = Capybara.string(response.body)
          expect(html.find("#providers_position_0")).to have_text("1 de", exact: true)
        end
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

      it "marks the results heading with the target JS uses to announce it to screen readers" do
        get :show, params: { query: "unemployed" }
        expect(response).to be_successful
        expect(response.body).to include('data-cbv-employer-search-target="resultsHeading"')
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

      it "shows 'Search results' as the page header once a query is present" do
        get :show, params: { query: "results" }

        html = Capybara.string(response.body)
        expect(html.find("#employer-search-h1").text.strip).to eq("Search results")
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

      it "renders the back to top button with correct tracking attributes" do
        get :show, params: { query: "results" }

        html = Capybara.string(response.body)
        back_to_top = html.find("button[data-element-name='back_to_top']")
        expect(back_to_top["data-action"]).to include("click->click-tracker#track")
        expect(back_to_top["data-track-event"]).to eq("ApplicantClickedGoBackToTop")
        expect(back_to_top["data-element-type"]).to eq("anchor_link")
        expect(back_to_top["data-context-query"]).to eq("results")
      end

      it "downcases the search query on the back to top tracking context" do
        get :show, params: { query: "ReSuLtS" }

        html = Capybara.string(response.body)
        back_to_top = html.find("button[data-element-name='back_to_top']")
        expect(back_to_top["data-context-query"]).to eq("results")
      end

      context "when there are fewer than 5 results" do
        before do
          # hack the BLOCKED_ARGYLE_EMPLOYERS constant to remove 1 result from bob's default 5 results.
          stub_const("ProviderSearchService::BLOCKED_ARGYLE_EMPLOYERS", [ "item_000017502" ])
        end

        it "does not render the back to top button" do
          get :show, params: { query: "results" }

          expect(response).to be_successful
          expect(Capybara.string(response.body)).to have_no_css("button[data-element-name='back_to_top']")
        end
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
