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
end
