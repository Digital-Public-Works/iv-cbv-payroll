require "rails_helper"

RSpec.describe "Pages", type: :request do
  describe "GET /home" do
    it "returns http success" do
      get "/"
      expect(response).to have_http_status(:success)
    end

    context "when the maintenance mode is enabled" do
      around do |ex|
        stub_environment_variable("MAINTENANCE_MODE", "true", &ex)
      end

      it "redirects to maintenance path" do
        get "/"

        expect(response).to redirect_to(maintenance_path)
      end
    end

    context "when the maintenance mode is disabled" do
      around do |ex|
        stub_environment_variable("MAINTENANCE_MODE", nil, &ex)
      end

      it "renders the correct path" do
        get "/"

        expect(response).to render_template(:home)
      end
    end

    # Screen readers only move their reading position when the skip link's
    # target can actually receive focus, which a <main> needs tabindex="-1" for.
    it "renders a skip link whose target is programmatically focusable" do
      get "/"

      page = Nokogiri::HTML(response.body)
      expect(page.at_css("a.usa-skipnav")["href"]).to eq("#main-content")
      expect(page.at_css("main#main-content")["tabindex"]).to eq("-1")
    end
  end
end
