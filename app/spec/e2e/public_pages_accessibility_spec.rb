require "rails_helper"

# Pages outside the main applicant flow, reached by visiting them directly.
RSpec.describe "Public pages accessibility", :js, type: :feature do
  include E2e::TestHelpers

  it "checks the home page" do
    visit root_path
    # The home page renders here rather than redirecting into the generic flow
    expect(page).to have_current_path(root_path)
    verify_page(page, title: I18n.t("pages.home.header"))
  end

  it "checks the home page after a session timeout" do
    visit root_path(cbv_flow_timeout: true)
    # The timeout variant adds an info alert above the home page content
    expect(page).to have_selector("#slim-alert.usa-alert--info")
    verify_page(page, title: I18n.t("pages.home.header"))
  end

  it "checks the session timeout page" do
    visit cbv_flow_session_timeout_path(client_agency_id: "sandbox")
    # Without a valid partner this redirects to the home page timeout variant
    expect(page).to have_current_path(cbv_flow_session_timeout_path(client_agency_id: "sandbox"))
    verify_page(page, title: I18n.t("session_timeout.page.title"))
  end

  it "checks the maintenance page" do
    visit maintenance_path
    expect(page).to have_current_path(maintenance_path)
    verify_page(page, title: I18n.t("maintenance.header"))
  end

  it "checks the 404 page" do
    # Visited directly: the test env raises errors instead of rendering this page
    visit "/404"
    expect(page).to have_link(I18n.t("pages.error_404.return_to_welcome"))
    verify_page(page, title: I18n.t("pages.error_404.header"))
  end

  it "checks the 500 page" do
    # Visited directly for the same reason as the 404 page
    visit "/500"
    expect(page).to have_link(I18n.t("pages.error_500.refresh"))
    verify_page(page, title: I18n.t("pages.error_500.header"))
  end
end
