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
      expect(response.body).to include("Verify My Income did not find pay stub images for these jobs")
    end

    it "lists only the with-image jobs when every job has images" do
      preview_get "/cbv/preview/submit_pdf_as_html", fixture: "paystubs_all_images"
      expect(response.body).to include("There are pay stub images for these jobs")
      expect(response.body).not_to include("Verify My Income did not find pay stub images")
    end

    # The cover page still appears with no images, so the absence is explicit
    # rather than the section silently vanishing from the report.
    it "reassures the client and lists every job when there are no images" do
      preview_get "/cbv/preview/submit_pdf_as_html", fixture: "paystubs_no_images"
      expect(response.body).to include("Income Verification Report: Pay stub images")
      expect(response.body).to include("Verify My Income did not find pay stub images for these jobs")
      expect(response.body).not_to include("There are pay stub images for these jobs")
    end

    # The intro reassures the client regardless of how many images were found,
    # so it is no longer conditional on the with/without split.
    %w[paystubs_all_images paystubs_some_images paystubs_no_images].each do |fixture|
      it "always shows the accuracy intro (#{fixture})" do
        preview_get "/cbv/preview/submit_pdf_as_html", fixture: fixture
        expect(response.body).to include("Pay stub images do not impact your income report")
        expect(response.body).not_to include("they are shown on the next page")
      end
    end
  end

  # The info box always points the caseworker at the separate pay stub images
  # file and never enumerates which jobs did or did not have images.
  describe "caseworker income report info box" do
    %w[paystubs_all_images paystubs_some_images paystubs_no_images].each do |fixture|
      it "points to the separate pay stub images file without listing jobs (#{fixture})" do
        preview_get "/cbv/preview/submit_pdf_as_html", fixture: fixture, extra: { is_caseworker: "true" }
        expect(response.body).to include("Pay stub images")
        expect(response.body).to include("Pay stub images are provided in a separate file for reference, when available.")
        expect(response.body).not_to include("The following jobs have pay stub images")
        expect(response.body).not_to include("Verify My Income did not find pay stub images")
      end
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
