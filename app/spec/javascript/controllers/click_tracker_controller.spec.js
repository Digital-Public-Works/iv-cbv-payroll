import { vi, describe, afterEach, it, expect } from "vitest"
import { Application } from "@hotwired/stimulus"
import ClickTrackerController from "@js/controllers/click_tracker_controller.js"

vi.mock("@js/utilities/api", () => ({
  trackUserAction: vi.fn(),
}))
import { trackUserAction } from "@js/utilities/api"

async function setupController(html) {
  document.body.innerHTML = html
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
      application = await setupController(`
        <div data-controller="click-tracker" data-click-tracker-page-value="missing_results" data-context-jobs-already-added="0">
          <a id="link" href="#test" data-action="click->click-tracker#track" data-track-type="anchor_link" data-track-name="test_link">Test</a>
        </div>
      `)
      document.getElementById("link").click()
      expect(trackUserAction).toHaveBeenCalledWith("ApplicantClickedElement", {
        element_type: "anchor_link",
        element_tag_name: "a",
        element_name: "test_link",
        page: "missing_results",
        jobs_already_added: 0,
      })
    })

    it("defaults element_type to generic when not specified", async () => {
      application = await setupController(`
        <div data-controller="click-tracker" data-click-tracker-page-value="test_page">
          <a id="link" href="#test" data-action="click->click-tracker#track" data-track-name="test_link">Test</a>
        </div>
      `)
      document.getElementById("link").click()
      expect(trackUserAction).toHaveBeenCalledWith(
        "ApplicantClickedElement",
        expect.objectContaining({
          element_type: "generic",
        })
      )
    })

    it("includes element_tag_name for anchor elements", async () => {
      application = await setupController(`
        <div data-controller="click-tracker" data-click-tracker-page-value="test_page">
          <a id="link" href="#test" data-action="click->click-tracker#track" data-track-name="anchor_link">Test</a>
        </div>
      `)
      document.getElementById("link").click()
      expect(trackUserAction).toHaveBeenCalledWith(
        "ApplicantClickedElement",
        expect.objectContaining({
          element_tag_name: "a",
        })
      )
    })

    it("includes element_tag_name for button elements", async () => {
      application = await setupController(`
        <div data-controller="click-tracker" data-click-tracker-page-value="test_page">
          <button id="btn" data-action="click->click-tracker#track" data-track-type="accordion" data-track-name="test_button">Test</button>
        </div>
      `)
      document.getElementById("btn").click()
      expect(trackUserAction).toHaveBeenCalledWith(
        "ApplicantClickedElement",
        expect.objectContaining({
          element_type: "accordion",
          element_tag_name: "button",
        })
      )
    })

    it("includes context values from data-context-* attributes", async () => {
      application = await setupController(`
        <div data-controller="click-tracker" data-click-tracker-page-value="test_page" data-context-jobs-already-added="3">
          <a id="link" href="#test" data-action="click->click-tracker#track" data-track-name="test">Test</a>
        </div>
      `)
      document.getElementById("link").click()
      expect(trackUserAction).toHaveBeenCalledWith(
        "ApplicantClickedElement",
        expect.objectContaining({
          jobs_already_added: 3,
        })
      )
    })

    it("supports multiple context attributes", async () => {
      application = await setupController(`
        <div data-controller="click-tracker" data-click-tracker-page-value="test_page" data-context-jobs-already-added="2" data-context-user-type="applicant">
          <a id="link" href="#test" data-action="click->click-tracker#track" data-track-name="test">Test</a>
        </div>
      `)
      document.getElementById("link").click()
      expect(trackUserAction).toHaveBeenCalledWith(
        "ApplicantClickedElement",
        expect.objectContaining({
          jobs_already_added: 2,
          user_type: "applicant",
        })
      )
    })

    it("includes page value from controller", async () => {
      application = await setupController(`
        <div data-controller="click-tracker" data-click-tracker-page-value="custom_page">
          <a id="link" href="#test" data-action="click->click-tracker#track" data-track-name="test">Test</a>
        </div>
      `)
      document.getElementById("link").click()
      expect(trackUserAction).toHaveBeenCalledWith(
        "ApplicantClickedElement",
        expect.objectContaining({
          page: "custom_page",
        })
      )
    })

    describe("missing_results page elements", () => {
      it("tracks anchor link with anchor_link type", async () => {
        application = await setupController(`
          <div data-controller="click-tracker" data-click-tracker-page-value="missing_results" data-context-jobs-already-added="2">
            <a id="link" href="#search-tips" data-action="click->click-tracker#track" data-track-type="anchor_link" data-track-name="search_tips_anchor">Search tips</a>
          </div>
        `)
        document.getElementById("link").click()
        expect(trackUserAction).toHaveBeenCalledWith("ApplicantClickedElement", {
          element_type: "anchor_link",
          element_tag_name: "a",
          element_name: "search_tips_anchor",
          page: "missing_results",
          jobs_already_added: 2,
        })
      })

      it("tracks accordion button with accordion type", async () => {
        application = await setupController(`
          <div data-controller="click-tracker" data-click-tracker-page-value="missing_results" data-context-jobs-already-added="1">
            <button id="btn" data-action="click->click-tracker#track" data-track-type="accordion" data-track-name="payroll_provider_help">Help</button>
          </div>
        `)
        document.getElementById("btn").click()
        expect(trackUserAction).toHaveBeenCalledWith("ApplicantClickedElement", {
          element_type: "accordion",
          element_tag_name: "button",
          element_name: "payroll_provider_help",
          page: "missing_results",
          jobs_already_added: 1,
        })
      })

      it("tracks internal link with internal_link type", async () => {
        application = await setupController(`
          <div data-controller="click-tracker" data-click-tracker-page-value="missing_results" data-context-jobs-already-added="0">
            <a id="link" href="/search" data-action="click->click-tracker#track" data-track-type="internal_link" data-track-name="try_searching_again">Try again</a>
          </div>
        `)
        document.getElementById("link").click()
        expect(trackUserAction).toHaveBeenCalledWith("ApplicantClickedElement", {
          element_type: "internal_link",
          element_tag_name: "a",
          element_name: "try_searching_again",
          page: "missing_results",
          jobs_already_added: 0,
        })
      })

      it("tracks external link with external_link type", async () => {
        application = await setupController(`
          <div data-controller="click-tracker" data-click-tracker-page-value="missing_results" data-context-jobs-already-added="0">
            <a id="link" href="https://agency.gov" data-action="click->click-tracker#track" data-track-type="external_link" data-track-name="go_to_agency_portal">Go to portal</a>
          </div>
        `)
        document.getElementById("link").click()
        expect(trackUserAction).toHaveBeenCalledWith("ApplicantClickedElement", {
          element_type: "external_link",
          element_tag_name: "a",
          element_name: "go_to_agency_portal",
          page: "missing_results",
          jobs_already_added: 0,
        })
      })
    })
  })
})
