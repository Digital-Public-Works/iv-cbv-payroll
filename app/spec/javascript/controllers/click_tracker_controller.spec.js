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
          <a id="link" href="#test" data-action="click->click-tracker#track" data-element-type="anchor_link" data-element-name="test_link">Test</a>
        </div>
      `)
      document.getElementById("link").click()
      expect(trackUserAction).toHaveBeenCalledWith("ApplicantClickedElement", {
        "click.element_type": "anchor_link",
        "click.element_tag_name": "a",
        "click.element_name": "test_link",
        "click.page": "missing_results",
        "click_context.jobs_already_added": 0,
      })
    })

    it("defaults element_type to generic when not specified", async () => {
      application = await setupController(`
        <div data-controller="click-tracker" data-click-tracker-page-value="test_page">
          <a id="link" href="#test" data-action="click->click-tracker#track" data-element-name="test_link">Test</a>
        </div>
      `)
      document.getElementById("link").click()
      expect(trackUserAction).toHaveBeenCalledWith(
        "ApplicantClickedElement",
        expect.objectContaining({
          "click.element_type": "generic",
        })
      )
    })

    it("includes element_tag_name for anchor elements", async () => {
      application = await setupController(`
        <div data-controller="click-tracker" data-click-tracker-page-value="test_page">
          <a id="link" href="#test" data-action="click->click-tracker#track" data-element-name="anchor_link">Test</a>
        </div>
      `)
      document.getElementById("link").click()
      expect(trackUserAction).toHaveBeenCalledWith(
        "ApplicantClickedElement",
        expect.objectContaining({
          "click.element_tag_name": "a",
        })
      )
    })

    it("includes element_tag_name for button elements", async () => {
      application = await setupController(`
        <div data-controller="click-tracker" data-click-tracker-page-value="test_page">
          <button id="btn" data-action="click->click-tracker#track" data-element-type="accordion" data-element-name="test_button">Test</button>
        </div>
      `)
      document.getElementById("btn").click()
      expect(trackUserAction).toHaveBeenCalledWith(
        "ApplicantClickedElement",
        expect.objectContaining({
          "click.element_type": "accordion",
          "click.element_tag_name": "button",
        })
      )
    })

    it("includes context values from data-context-* attributes", async () => {
      application = await setupController(`
        <div data-controller="click-tracker" data-click-tracker-page-value="test_page" data-context-jobs-already-added="3">
          <a id="link" href="#test" data-action="click->click-tracker#track" data-element-name="test">Test</a>
        </div>
      `)
      document.getElementById("link").click()
      expect(trackUserAction).toHaveBeenCalledWith(
        "ApplicantClickedElement",
        expect.objectContaining({
          "click_context.jobs_already_added": 3,
        })
      )
    })

    it("supports multiple context attributes", async () => {
      application = await setupController(`
        <div data-controller="click-tracker" data-click-tracker-page-value="test_page" data-context-jobs-already-added="2" data-context-user-type="applicant">
          <a id="link" href="#test" data-action="click->click-tracker#track" data-element-name="test">Test</a>
        </div>
      `)
      document.getElementById("link").click()
      expect(trackUserAction).toHaveBeenCalledWith(
        "ApplicantClickedElement",
        expect.objectContaining({
          "click_context.jobs_already_added": 2,
          "click_context.user_type": "applicant",
        })
      )
    })

    it("includes page value from controller", async () => {
      application = await setupController(`
        <div data-controller="click-tracker" data-click-tracker-page-value="custom_page">
          <a id="link" href="#test" data-action="click->click-tracker#track" data-element-name="test">Test</a>
        </div>
      `)
      document.getElementById("link").click()
      expect(trackUserAction).toHaveBeenCalledWith(
        "ApplicantClickedElement",
        expect.objectContaining({
          "click.page": "custom_page",
        })
      )
    })

    it("uses custom event name from data-track-event", async () => {
      application = await setupController(`
        <div data-controller="click-tracker" data-click-tracker-page-value="test_page">
          <a id="link" href="#test" data-action="click->click-tracker#track" data-element-name="test" data-track-event="ApplicantClickedSearchTips">Test</a>
        </div>
      `)
      document.getElementById("link").click()
      expect(trackUserAction).toHaveBeenCalledWith(
        "ApplicantClickedSearchTips",
        expect.objectContaining({
          "click.element_name": "test",
        })
      )
    })

    describe("missing_results page elements", () => {
      it("tracks anchor link with anchor_link type", async () => {
        application = await setupController(`
          <div data-controller="click-tracker" data-click-tracker-page-value="missing_results" data-context-jobs-already-added="2">
            <a id="link" href="#search-tips" data-action="click->click-tracker#track" data-element-type="anchor_link" data-element-name="search_tips_anchor">Search tips</a>
          </div>
        `)
        document.getElementById("link").click()
        expect(trackUserAction).toHaveBeenCalledWith("ApplicantClickedElement", {
          "click.element_type": "anchor_link",
          "click.element_tag_name": "a",
          "click.element_name": "search_tips_anchor",
          "click.page": "missing_results",
          "click_context.jobs_already_added": 2,
        })
      })

      it("tracks accordion button with accordion type", async () => {
        application = await setupController(`
          <div data-controller="click-tracker" data-click-tracker-page-value="missing_results" data-context-jobs-already-added="1">
            <button id="btn" data-action="click->click-tracker#track" data-element-type="accordion" data-element-name="payroll_provider_help">Help</button>
          </div>
        `)
        document.getElementById("btn").click()
        expect(trackUserAction).toHaveBeenCalledWith("ApplicantClickedElement", {
          "click.element_type": "accordion",
          "click.element_tag_name": "button",
          "click.element_name": "payroll_provider_help",
          "click.page": "missing_results",
          "click_context.jobs_already_added": 1,
        })
      })

      it("tracks internal link with internal_link type", async () => {
        application = await setupController(`
          <div data-controller="click-tracker" data-click-tracker-page-value="missing_results" data-context-jobs-already-added="0">
            <a id="link" href="#search" data-action="click->click-tracker#track" data-element-type="internal_link" data-element-name="try_searching_again">Try again</a>
          </div>
        `)
        document.getElementById("link").click()
        expect(trackUserAction).toHaveBeenCalledWith("ApplicantClickedElement", {
          "click.element_type": "internal_link",
          "click.element_tag_name": "a",
          "click.element_name": "try_searching_again",
          "click.page": "missing_results",
          "click_context.jobs_already_added": 0,
        })
      })

      it("tracks external link with external_link type", async () => {
        application = await setupController(`
          <div data-controller="click-tracker" data-click-tracker-page-value="missing_results" data-context-jobs-already-added="0">
            <a id="link" href="https://agency.gov" data-action="click->click-tracker#track" data-element-type="external_link" data-element-name="go_to_agency_portal">Go to portal</a>
          </div>
        `)
        document.getElementById("link").click()
        expect(trackUserAction).toHaveBeenCalledWith("ApplicantClickedElement", {
          "click.element_type": "external_link",
          "click.element_tag_name": "a",
          "click.element_name": "go_to_agency_portal",
          "click.page": "missing_results",
          "click_context.jobs_already_added": 0,
        })
      })
    })
  })
})
