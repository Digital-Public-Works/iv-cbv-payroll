require "rails_helper"

RSpec.describe "Help Features", :js, type: :feature do
  include E2e::TestHelpers
  include PinwheelApiHelper
  include ApplicationHelper

  let(:cbv_flow_invitation) { create(:cbv_flow_invitation) }
  let(:cbv_flow) { create(:cbv_flow, :invited, cbv_flow_invitation: cbv_flow_invitation) }

  before(:all) do
    WebMock.allow_net_connect!
  end

  after(:all) do
    WebMock.disable_net_connect!
  end

  context "When in the applicant flow" do
    before do
      visit URI(cbv_flow_invitation.to_url).request_uri
      verify_page(page, title: I18n.t("cbv.entries.show.header", agency_full_name: I18n.t("shared.agency_full_name.sandbox")))
      find("[data-testid='attestation-checkbox']").click
      click_button I18n.t("cbv.entries.show.continue")
    end

    it "opens help modal when clicking link in help banner" do
      visit cbv_flow_employer_search_path
      click_link "Help"

      expect(page).to have_selector(".usa-modal__content", visible: true)
    end

    it "displays correct content in the help modal" do
      visit cbv_flow_employer_search_path
      click_link "Help"

      expect(page).to have_selector(".usa-modal__content", visible: true)

      within(".usa-modal__content") do
        verify_page(page, title: I18n.t("help.index.title"))
        expect(page).to have_content(I18n.t("help.index.select_prompt"))

        # Verify all help topic buttons are present
        expect(page).to have_button(I18n.t("help.index.username"))
        expect(page).to have_button(I18n.t("help.index.password"))
        expect(page).to have_button(I18n.t("help.index.company_id"))
        expect(page).to have_button(I18n.t("help.index.employer"))
        expect(page).to have_button(I18n.t("help.index.provider"))
        expect(page).to have_button(I18n.t("help.index.credentials"))

        # Verify feedback link opens in new tab with correct URL
        feedback_link = find_link(I18n.t("help.index.feedback"))
        expect(feedback_link[:href]).to eq(ApplicationHelper::APPLICANT_FEEDBACK_FORM)
        expect(feedback_link[:target]).to eq("_blank")
      end
    end


    it "can navigate between help topics" do
      visit cbv_flow_employer_search_path
      click_link "Help"

      expect(page).to have_selector(".usa-modal__content", visible: true)

      within(".usa-modal__content") do
        click_button I18n.t("help.index.username")
        verify_page(page, title: I18n.t("help.show.username.title"))

        click_button I18n.t("help.show.go_back")
        verify_page(page, title: I18n.t("help.index.title"))
      end
    end

    it "resets to the topic list when reopened after viewing a topic" do
      visit cbv_flow_employer_search_path
      click_link "Help"

      within(".usa-modal__content") do
        click_button I18n.t("help.index.username")
        verify_page(page, title: I18n.t("help.show.username.title"))
      end

      find("button[aria-label='Close this window']").click
      expect(page).not_to have_selector(".usa-modal__content", visible: true)

      # The reset should already have happened while the modal is hidden,
      # not wait for the next open - otherwise the stale topic would
      # visibly flash before swapping back to the topic list.
      expect(page).to have_selector("turbo-frame#help_modal_content[src$='/help']", visible: false)

      click_link "Help"

      within(".usa-modal__content") do
        verify_page(page, title: I18n.t("help.index.title"))
      end
    end

    it "keeps focus trapped in the modal after navigating to a topic and going back" do
      visit cbv_flow_employer_search_path
      click_link "Help"

      expect(page).to have_selector(".usa-modal__content", visible: true)

      within(".usa-modal__content") do
        click_button I18n.t("help.index.username")
        verify_page(page, title: I18n.t("help.show.username.title"))

        # Focus should return to the modal container, not to an arbitrary
        # interactive element like "Go Back" just because it's first in the
        # DOM, and not into the swapped content itself (which would anchor a
        # screen reader's virtual cursor there).
        expect(page.evaluate_script("document.activeElement.classList.contains('usa-modal')")).to be(true)

        click_button I18n.t("help.show.go_back")
        verify_page(page, title: I18n.t("help.index.title"))

        expect(page.evaluate_script("document.activeElement.classList.contains('usa-modal')")).to be(true)
      end

      # Simulate a keyboard user tabbing all the way to the modal's Close button.
      page.execute_script(<<~JS)
        document.querySelector('button[aria-label="Close this window"]').focus()
      JS

      find("body").send_keys(:tab)
      expect(page.evaluate_script("document.activeElement.textContent.trim()"))
        .to eq(I18n.t("help.index.username"))

      find("body").send_keys(%i[shift tab])
      expect(page.evaluate_script("document.activeElement.getAttribute('aria-label')"))
        .to eq("Close this window")
    end

    it "can shift+tab backward after navigating to a topic and going back, modal still open" do
      visit cbv_flow_employer_search_path
      click_link "Help"

      within(".usa-modal__content") do
        click_button I18n.t("help.index.username")
        verify_page(page, title: I18n.t("help.show.username.title"))

        click_button I18n.t("help.show.go_back")
        verify_page(page, title: I18n.t("help.index.title"))
      end

      # Regression check: USWDS's own focus trap from when the modal first
      # opened (a separate instance our code can't reach or clean up) has a
      # catch-all in its Shift+Tab handling that used to fire on every
      # keypress after any content swap and swallow it, leaving the user
      # stuck unable to tab backward at all - even from the very first item.
      first_topic = find_button(I18n.t("help.index.username"))
      first_topic.send_keys(%i[shift tab])

      expect(page.evaluate_script("document.activeElement.getAttribute('aria-label')"))
        .to eq("Close this window")
    end

    it "activates a topic button with the space key" do
      visit cbv_flow_employer_search_path
      click_link "Help"

      expect(page).to have_selector(".usa-modal__content", visible: true)

      within(".usa-modal__content") do
        find_button(I18n.t("help.index.username")).send_keys(:space)
        verify_page(page, title: I18n.t("help.show.username.title"))
      end
    end

    it "does not trap Tab/Shift+Tab elsewhere on the page after closing via Escape post-navigation" do
      visit cbv_flow_employer_search_path
      click_link "Help"

      within(".usa-modal__content") do
        click_button I18n.t("help.index.username")
        verify_page(page, title: I18n.t("help.show.username.title"))
      end

      find("body").send_keys(:escape)
      expect(page).not_to have_selector(".usa-modal__content", visible: true)

      # Regression check: a leaked focus-trap keydown listener (from a fix
      # that mistakenly read/wrote a *different* USWDS module instance's
      # shared "modal" singleton than the one actually driving the page)
      # used to keep intercepting Shift+Tab site-wide after this exact
      # sequence, redirecting focus back into the now-hidden modal.
      page.execute_script("document.querySelector('a[href=\"#help-modal\"]').focus()")
      find("body").send_keys(%i[shift tab])
      expect(page.evaluate_script("document.activeElement.closest('.usa-modal-wrapper') !== null"))
        .to be(false)
    end

    it "closes help modal when clicking close button" do
      visit cbv_flow_employer_search_path
      click_link "Help"

      # Wait for modal to be visible
      expect(page).to have_selector(".usa-modal__content", visible: true)

      find("button[aria-label='Close this window']").click
      expect(page).not_to have_selector(".usa-modal__content", visible: true)
    end
  end

  context "When in the caseworker flow" do
    it "displays correct content in the help modal" do
      visit new_user_session_path(client_agency_id: "sandbox")
      click_link "Help"

      expect(page).to have_selector(".usa-modal__content", visible: true)

      within(".usa-modal__content") do
        verify_page(page, title: I18n.t("help.index.title"))
        expect(page).to have_content(I18n.t("help.index.select_prompt"))

        # Verify all help topic buttons are present
        expect(page).to have_button(I18n.t("help.index.username"))
        expect(page).to have_button(I18n.t("help.index.password"))
        expect(page).to have_button(I18n.t("help.index.company_id"))
        expect(page).to have_button(I18n.t("help.index.employer"))
        expect(page).to have_button(I18n.t("help.index.provider"))
        expect(page).to have_button(I18n.t("help.index.credentials"))

        # Caseworker should not see the feedback flow
        expect(page).not_to have_link(I18n.t("help.index.feedback"))
      end
    end
  end
end
