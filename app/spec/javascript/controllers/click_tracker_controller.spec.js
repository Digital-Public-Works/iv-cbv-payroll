import { vi, describe, beforeEach, afterEach, it, expect } from "vitest"
import { Application } from "@hotwired/stimulus"
import ClickTrackerController from "@js/controllers/click_tracker_controller.js"

vi.mock("@js/utilities/api", () => ({
  trackUserAction: vi.fn(),
}))
import { trackUserAction } from "@js/utilities/api"

async function setupController(
  innerHTML,
  page = "missing_results",
  context = { jobs_already_added: 0 }
) {
  document.body.innerHTML = `
    <div data-controller="click-tracker" data-click-tracker-page-value="${page}" data-click-tracker-context-value='${JSON.stringify(context)}'>
      ${innerHTML}
    </div>
  `
  const application = Application.start()
  application.register("click-tracker", ClickTrackerController)
  await new Promise((resolve) => setTimeout(resolve, 0))
  return application
}

describe("click_tracker_controller", () => {
  let application

  afterEach(() => {
    application?.stop()
    document.body.innerHTML = ""
    vi.resetAllMocks()
  })

  describe("track", () => {
    it("tracks ApplicantClickedElement with element properties", async () => {
      application = await setupController(
        `
        <a id="link" href="#test" data-action="click->click-tracker#track" data-track-name="test_link">Test</a>
      `,
        "missing_results",
        { jobs_already_added: 0 }
      )
      document.getElementById("link").click()
      expect(trackUserAction).toHaveBeenCalledWith("ApplicantClickedElement", {
        element_tag_name: "a",
        element_name: "test_link",
        page: "missing_results",
        jobs_already_added: 0,
      })
    })

    it("uses tag name for anchor elements", async () => {
      application = await setupController(
        `
        <a id="link" href="#test" data-action="click->click-tracker#track" data-track-name="anchor_link">Test</a>
      `,
        "missing_results",
        { jobs_already_added: 0 }
      )
      document.getElementById("link").click()
      expect(trackUserAction).toHaveBeenCalledWith(
        "ApplicantClickedElement",
        expect.objectContaining({
          element_tag_name: "a",
        })
      )
    })

    it("uses tag name for button elements", async () => {
      application = await setupController(
        `
        <button id="btn" data-action="click->click-tracker#track" data-track-name="test_button">Test</button>
      `,
        "missing_results",
        { jobs_already_added: 0 }
      )
      document.getElementById("btn").click()
      expect(trackUserAction).toHaveBeenCalledWith(
        "ApplicantClickedElement",
        expect.objectContaining({
          element_tag_name: "button",
        })
      )
    })

    it("includes context values from controller", async () => {
      application = await setupController(
        `
        <a id="link" href="#test" data-action="click->click-tracker#track" data-track-name="test">Test</a>
      `,
        "missing_results",
        { jobs_already_added: 3 }
      )
      document.getElementById("link").click()
      expect(trackUserAction).toHaveBeenCalledWith(
        "ApplicantClickedElement",
        expect.objectContaining({
          jobs_already_added: 3,
        })
      )
    })

    it("includes page value from controller", async () => {
      application = await setupController(
        `
        <a id="link" href="#test" data-action="click->click-tracker#track" data-track-name="test">Test</a>
      `,
        "custom_page",
        { jobs_already_added: 0 }
      )
      document.getElementById("link").click()
      expect(trackUserAction).toHaveBeenCalledWith(
        "ApplicantClickedElement",
        expect.objectContaining({
          page: "custom_page",
        })
      )
    })

    describe("missing_results page specific elements", () => {
      it("tracks search tips anchor link", async () => {
        application = await setupController(
          `
          <a id="link" href="#search-tips" data-action="click->click-tracker#track" data-track-name="search_tips_anchor">Search tips</a>
        `,
          "missing_results",
          { jobs_already_added: 2 }
        )
        document.getElementById("link").click()
        expect(trackUserAction).toHaveBeenCalledWith("ApplicantClickedElement", {
          element_tag_name: "a",
          element_name: "search_tips_anchor",
          page: "missing_results",
          jobs_already_added: 2,
        })
      })

      it("tracks payroll provider help accordion button", async () => {
        application = await setupController(
          `
          <button id="btn" data-action="click->click-tracker#track" data-track-name="payroll_provider_help">Help</button>
        `,
          "missing_results",
          { jobs_already_added: 1 }
        )
        document.getElementById("btn").click()
        expect(trackUserAction).toHaveBeenCalledWith("ApplicantClickedElement", {
          element_tag_name: "button",
          element_name: "payroll_provider_help",
          page: "missing_results",
          jobs_already_added: 1,
        })
      })

      it("tracks try searching again link", async () => {
        application = await setupController(
          `
          <a id="link" href="/search" data-action="click->click-tracker#track" data-track-name="try_searching_again">Try again</a>
        `,
          "missing_results",
          { jobs_already_added: 0 }
        )
        document.getElementById("link").click()
        expect(trackUserAction).toHaveBeenCalledWith("ApplicantClickedElement", {
          element_tag_name: "a",
          element_name: "try_searching_again",
          page: "missing_results",
          jobs_already_added: 0,
        })
      })

      it("tracks go to agency portal link", async () => {
        application = await setupController(
          `
          <a id="link" href="https://agency.gov" data-action="click->click-tracker#track" data-track-name="go_to_agency_portal">Go to portal</a>
        `,
          "missing_results",
          { jobs_already_added: 0 }
        )
        document.getElementById("link").click()
        expect(trackUserAction).toHaveBeenCalledWith("ApplicantClickedElement", {
          element_tag_name: "a",
          element_name: "go_to_agency_portal",
          page: "missing_results",
          jobs_already_added: 0,
        })
      })

      it("tracks go to income summary link", async () => {
        application = await setupController(
          `
          <a id="link" href="/summary" data-action="click->click-tracker#track" data-track-name="go_to_income_summary">Continue</a>
        `,
          "missing_results",
          { jobs_already_added: 2 }
        )
        document.getElementById("link").click()
        expect(trackUserAction).toHaveBeenCalledWith("ApplicantClickedElement", {
          element_tag_name: "a",
          element_name: "go_to_income_summary",
          page: "missing_results",
          jobs_already_added: 2,
        })
      })
    })
  })
})
