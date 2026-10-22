require "rails_helper"

RSpec.describe PagesController do
  render_views

  describe "#home" do
    it "renders" do
      get :home
      expect(response).to be_successful
      expect(response.body).to include("Welcome")
    end

    context "when on the subdomain of a partner that offers the generic flow" do
      before do
        stub_client_agency_config_value("sandbox", "agency_domain", "sandbox.verifymyincome.org")
        request.host = "sandbox.verifymyincome.org"
      end

      it "sends the applicant into the generic flow at /start" do
        get :home
        expect(response).to redirect_to(start_path)
      end

      it "passes a provided origin parameter along to /start" do
        get :home, params: { origin: "mail" }
        expect(response).to redirect_to(start_path(origin: "mail"))
      end
    end

    context "when a partner has been wound down (both flows off)" do
      before do
        stub_client_agency_config_value("sandbox", "agency_domain", "sandbox.verifymyincome.org")
        stub_client_agency_config_value("sandbox", "generic_links_enabled", false)
        stub_client_agency_config_value("sandbox", "invitation_links_enabled", false)
      end

      it "stays on the landing page instead of starting a flow" do
        request.host = "sandbox.verifymyincome.org"
        get :home
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Welcome")
      end
    end

    context "when agency has generic links disabled" do
      before do
        stub_client_agency_config_value("sandbox", "agency_domain", "sandbox.verifymyincome.org")
        stub_client_agency_config_value("sandbox", "generic_links_enabled", false)
      end

      it "does not redirect into the generic flow" do
        request.host = "sandbox.verifymyincome.org"
        get :home
        expect(response).not_to redirect_to(start_path)
        expect(response).to have_http_status(:ok)
      end
    end

    context "when cbv_flow_timeout param is present" do
      before do
        stub_client_agency_config_value("sandbox", "agency_domain", "sandbox.verifymyincome.org")
        request.host = "sandbox.verifymyincome.org"
        get :home, params: { cbv_flow_timeout: true }
      end

      it "does not redirect into the generic flow" do
        expect(response).not_to redirect_to(start_path)
        expect(response).to have_http_status(:ok)
      end

      it "renders the session timeout flash message" do
        expect(response.body).to include(I18n.t("cbv.error_missing_token_html").gsub("\n", " "))
      end
    end
  end

  describe "#error_404" do
    it "renders with a link to the homepage" do
      get :error_404
      expect(response.status).to eq(404)
      expect(response.body).to include("We can&#39;t find the page")
      expect(response.body).to include("Return to welcome")
    end

    describe "when a cbv_flow_id is in the session" do
      let(:cbv_flow) { create(:cbv_flow, :invited) }

      it "renders with a link to restart that CBV flow" do
        get :error_404, session: { cbv_flow_id: cbv_flow.id }
        expect(response.status).to eq(404)
        expect(response.body).to include("Return to entry page")
      end
    end

    describe "when on an agency subdomain" do
      let(:cbv_flow) { create(:cbv_flow, :invited) }

      it "renders" do
        request.host = "sandbox.verifymyincome.org"
        get :error_404, session: { cbv_flow_id: cbv_flow.id }
        expect(response.status).to eq(404)
        expect(response.body).to include("Return to entry page")
      end
    end
  end

  describe "#error_500" do
    it "renders" do
      get :error_500
      expect(response.status).to eq(500)
      expect(response.body).to include("It looks like something went wrong")
    end

    describe "when on an agency subdomain" do
      let(:cbv_flow) { create(:cbv_flow, :invited) }

      it "renders" do
        request.host = "sandbox.verifymyincome.org"
        get :error_500, session: { cbv_flow_id: cbv_flow.id }
        expect(response.status).to eq(500)
        expect(response.body).to include("It looks like something went wrong")
      end
    end
  end
end
