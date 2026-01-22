require "rails_helper"

RSpec.describe Cbv::ExpiredInvitationsController do
  describe "GET #show" do
    context "with a valid client_agency_id" do
      it "renders the show page" do
        get :show, params: { client_agency_id: "sandbox" }
        expect(response).to have_http_status(:ok)
      end
    end

    context "with an invalid client_agency_id" do
      it "redirects to root" do
        get :show, params: { client_agency_id: "invalid_agency" }
        expect(response).to redirect_to(root_url)
      end
    end

    context "without a client_agency_id" do
      it "redirects to root" do
        get :show
        expect(response).to redirect_to(root_url)
      end
    end

    context "with render_views" do
      render_views

      it "renders the expired invitation content for a valid agency" do
        get :show, params: { client_agency_id: "sandbox" }
        expect(response.body).to include(I18n.t("cbv.expired_invitations.show.title"))
      end
    end
  end
end
