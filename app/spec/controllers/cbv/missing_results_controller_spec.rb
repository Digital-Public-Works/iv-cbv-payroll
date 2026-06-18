require "rails_helper"

RSpec.describe Cbv::MissingResultsController do
  describe "#show" do
    render_views

    let(:cbv_flow) { create(:cbv_flow, :invited) }
    let(:event_logger) { instance_double(GenericEventTracker) }

    before do
      session[:cbv_flow_id] = cbv_flow.id
      allow(controller).to receive(:event_logger).and_return(event_logger)
      allow(event_logger).to receive(:track)
    end

    it "renders successfully" do
      get :show
      expect(response).to be_successful
    end

    describe "event tracking" do
      it "tracks ApplicantAccessedMissingResultsPage with version v2" do
        get :show
        expect(event_logger).to have_received(:track).with(
          TrackEvent::ApplicantAccessedMissingResultsPage,
          kind_of(ActionDispatch::Request),
          hash_including(
            cbv_flow_id: cbv_flow.id,
            version: "v2"
          )
        )
      end
    end

    it "renders the page header" do
      get :show
      expect(response.body).to include("Options to verify your income")
    end

    it "renders the quick links" do
      get :show
      expect(response.body).to include("Search tips")
      expect(response.body).to include("Other ways to verify job income")
    end

    it "renders the search tips section" do
      get :show
      expect(response.body).to include("Check your search term")
      expect(response.body).to include("Search for your payroll provider")
      # single quotes are html escaped
      expect(response.body).to include(ERB::Util.html_escape("Make sure you're searching for the right company"))
    end

    it "renders the accordion links for expandable content" do
      get :show
      expect(response.body).to include("How to find your payroll provider")
      expect(response.body).to include("How to find your employer")
      expect(response.body).to include("parent company")
      expect(response.body).to include("Other ways to submit income")
    end

    it "renders the try searching again button" do
      get :show
      expect(response.body).to include("Try searching again")
      expect(response.body).to include(cbv_flow_employer_search_path)
    end

    it "renders the other ways section heading" do
      get :show
      expect(response.body).to include("Other ways to verify job income")
    end

    context "when the user has NOT added any jobs" do
      it "renders the default intro text" do
        get :show
        expect(response.body).to include(ERB::Util.html_escape("if you can't find a job"))

        expect(response.body).to include("You may be able to upload documents")
      end

      it "renders the go to agency portal button" do
        get :show
        expect(response.body).to include("Go to VMI")
      end

      it "does not render the numbered steps" do
        get :show
        expect(response.body).not_to include("After submitting your income report")
      end

      it "does not render the continue to income summary button" do
        get :show
        expect(response.body).not_to include("Continue to Income Summary")
      end
    end

    context "when the user has a fully synced payroll account" do
      let!(:payroll_account) { create(:payroll_account, :argyle_fully_synced, cbv_flow: cbv_flow) }

      it "renders the intro text with job count" do
        get :show
        expect(response.body).to include("Since you have already logged into")
        expect(response.body).to include("1 job")
      end

      it "renders the numbered steps" do
        get :show
        expect(response.body).to include("Continue in Verify My Income to submit income information")
        expect(response.body).to include("After submitting your income report")
      end

      it "renders the continue to income summary button" do
        get :show
        expect(response.body).to include("Continue to Income Summary")
      end

      it "does not render the go to agency portal button" do
        get :show
        expect(response.body).not_to include("Go to VMI")
      end
    end

    context "when the user has a payroll account that is still syncing" do
      let!(:payroll_account) { create(:payroll_account, :argyle_sync_in_progress, cbv_flow: cbv_flow) }

      it "renders the default intro text (no jobs counted)" do
        get :show
        expect(response.body).to include("You may be able to upload documents")
      end

      it "renders the go to agency portal button" do
        get :show
        expect(response.body).to include("Go to VMI")
      end

      it "does not render the continue to income summary button" do
        get :show
        expect(response.body).not_to include("Continue to Income Summary")
      end
    end

    context "with multiple fully synced payroll accounts" do
      let!(:payroll_account1) { create(:payroll_account, :argyle_fully_synced, cbv_flow: cbv_flow) }
      let!(:payroll_account2) { create(:payroll_account, :argyle_fully_synced, cbv_flow: cbv_flow) }

      it "renders the plural form of job count" do
        get :show
        expect(response.body).to include("2 jobs")
      end
    end
  end
end
