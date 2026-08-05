require "rails_helper"

# Exercises the pay stub images preview endpoints end-to-end through the
# real controller + view stack (mock Argyle, no external calls). These guard
# the partial-lookup and locals wiring that a plain view spec would miss.
RSpec.describe "Cbv::Preview pay stub images", type: :request do
  def preview_get(path, fixture:, extra: {})
    get path, params: { include_paystubs: "true", client_agency_id: "sandbox", fixture_user: fixture }.merge(extra)
  end

  %w[paystubs_all_images paystubs_some_images paystubs_no_images].each do |fixture|
    context "fixture_user=#{fixture}" do
      it "renders the client income report (submit_pdf_as_html)" do
        preview_get "/cbv/preview/submit_pdf_as_html", fixture: fixture
        expect(response).to have_http_status(:ok)
      end

      it "renders the caseworker income report" do
        preview_get "/cbv/preview/submit_pdf_as_html", fixture: fixture, extra: { is_caseworker: "true" }
        expect(response).to have_http_status(:ok)
      end

      it "renders the caseworker pay stub images cover (paystubs_pdf_as_html)" do
        preview_get "/cbv/preview/paystubs_pdf_as_html", fixture: fixture
        expect(response).to have_http_status(:ok)
      end

      it "renders the transmitted JSON including paystub_images_included" do
        preview_get "/cbv/preview/transmitted_json", fixture: fixture
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("paystub_images_included")
      end
    end
  end

  describe "client report cover page content" do
    it "lists both the with- and without-image jobs for the mixed fixture" do
      preview_get "/cbv/preview/submit_pdf_as_html", fixture: "paystubs_some_images"
      expect(response.body).to include("There are pay stub images for these jobs")
      expect(response.body).to include("Verify My Income did not find pay stub images for the following jobs")
      expect(response.body).to include("they are shown on the next page")
      expect(response.body).not_to include("Your income report is accurate")
    end

    it "lists only the with-image jobs when every job has images" do
      preview_get "/cbv/preview/submit_pdf_as_html", fixture: "paystubs_all_images"
      expect(response.body).to include("There are pay stub images for these jobs")
      expect(response.body).to include("they are shown on the next page")
      expect(response.body).not_to include("Verify My Income did not find pay stub images")
      expect(response.body).not_to include("Your income report is accurate")
    end

    # The cover page still appears with no images, so the absence is explicit
    # rather than the section silently vanishing from the report.
    it "reassures the client and lists every job when there are no images" do
      preview_get "/cbv/preview/submit_pdf_as_html", fixture: "paystubs_no_images"
      expect(response.body).to include("Income Verification Report: Pay stub images")
      expect(response.body).to include("Your income report is accurate, even if there are no pay stub images")
      expect(response.body).to include("Verify My Income did not find pay stub images for the following jobs")
      expect(response.body).not_to include("There are pay stub images for these jobs")
      expect(response.body).not_to include("they are shown on the next page")
    end
  end

  describe "caseworker income report info box" do
    it "lists both groups when only some jobs have images" do
      preview_get "/cbv/preview/submit_pdf_as_html", fixture: "paystubs_some_images", extra: { is_caseworker: "true" }
      expect(response.body).to include("Pay stub images")
      expect(response.body).to include("The following jobs have pay stub images")
      expect(response.body).to include("Verify My Income did not find pay stub images for the following jobs")
      expect(response.body).to include("When available, pay stub images are provided in a separate file for reference")
      expect(response.body).to include("Aramark", "Target", "Walmart")
    end

    it "lists every job when they all have images" do
      preview_get "/cbv/preview/submit_pdf_as_html", fixture: "paystubs_all_images", extra: { is_caseworker: "true" }
      expect(response.body).to include("Pay stub images")
      expect(response.body).to include("The following jobs have pay stub images")
      expect(response.body).to include("Aramark", "Target", "Walmart")
      expect(response.body).to include("When available, pay stub images are provided in a separate file for reference")
      expect(response.body).not_to include("Verify My Income did not find pay stub images")
    end

    it "shows only the 'did not find' list when no job has images" do
      preview_get "/cbv/preview/submit_pdf_as_html", fixture: "paystubs_no_images", extra: { is_caseworker: "true" }
      expect(response.body).to include("Verify My Income did not find pay stub images for the following jobs")
      expect(response.body).not_to include("The following jobs have pay stub images")
      expect(response.body).not_to include("When available, pay stub images are provided in a separate file")
    end
  end

  describe "caseworker pay stub images cover content" do
    it "shows only the 'did not find' list when there are no images" do
      preview_get "/cbv/preview/paystubs_pdf_as_html", fixture: "paystubs_no_images"
      expect(response.body).to include("Verify My Income did not find pay stub images for the following jobs")
      expect(response.body).not_to include("Pay stubs are available for the jobs listed below")
    end
  end
end
