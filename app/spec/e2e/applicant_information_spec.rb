require "rails_helper"

RSpec.describe "Applicant information", :js, type: :feature do
  include E2e::TestHelpers

  # The generic entry point (/start) resolves its partner from the subdomain,
  # which the Capybara test server has no way to present, so start from the
  # tokenized link that /start would have redirected to.
  let(:invitation) do
    AutoInvitationService.new.create_for(client_agency_id: "sandbox")
  end

  it "allows a user to review their information" do
    # /start/:token
    visit start_flow_path(token: invitation.auth_token)

    # /cbv/applicant_information
    visit cbv_flow_applicant_information_path
    verify_page(page, title: I18n.t("cbv.applicant_informations.show.your_information"))
  end
end
