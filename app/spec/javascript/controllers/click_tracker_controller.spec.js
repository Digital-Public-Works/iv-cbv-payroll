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
    it("tracks click with element properties", async () => {
      application = await setupController(`
        <a id="link" href="#test"
           data-controller="click-tracker"
           data-click-tracker-page-value="test_page"
           data-action="click->click-tracker#track"
           data-element-type="anchor_link"
           data-element-name="test_link">Test</a>
      `)
      document.getElementById("link").click()
      expect(trackUserAction).toHaveBeenCalledWith("ApplicantClickedElement", {
        "click.element_type": "anchor_link",
        "click.element_tag_name": "a",
        "click.element_name": "test_link",
        "click.page": "test_page",
      })
    })

    it("defaults element_type to generic when not specified", async () => {
      application = await setupController(`
        <a id="link" href="#test"
           data-controller="click-tracker"
           data-click-tracker-page-value="test_page"
           data-action="click->click-tracker#track"
           data-element-name="test_link">Test</a>
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
        <a id="link" href="#test"
           data-controller="click-tracker"
           data-click-tracker-page-value="test_page"
           data-action="click->click-tracker#track"
           data-element-name="test_link">Test</a>
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
        <button id="btn"
                data-controller="click-tracker"
                data-click-tracker-page-value="test_page"
                data-action="click->click-tracker#track"
                data-element-type="accordion"
                data-element-name="test_button">Test</button>
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

    it("uses custom event name from data-track-event", async () => {
      application = await setupController(`
        <a id="link" href="#test"
           data-controller="click-tracker"
           data-click-tracker-page-value="test_page"
           data-action="click->click-tracker#track"
           data-element-name="search_tips"
           data-track-event="ApplicantClickedSearchTips">Test</a>
      `)
      document.getElementById("link").click()
      expect(trackUserAction).toHaveBeenCalledWith(
        "ApplicantClickedSearchTips",
        expect.objectContaining({
          "click.element_name": "search_tips",
        })
      )
    })

    describe("context data", () => {
      it("includes context from controller element", async () => {
        application = await setupController(`
          <div data-controller="click-tracker"
               data-click-tracker-page-value="missing_results"
               data-context-jobs-already-added="3">
            <a id="link" href="#test"
               data-action="click->click-tracker#track"
               data-element-name="test">Test</a>
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
          <div data-controller="click-tracker"
               data-click-tracker-page-value="test_page"
               data-context-jobs-already-added="2"
               data-context-user-type="applicant">
            <a id="link" href="#test"
               data-action="click->click-tracker#track"
               data-element-name="test">Test</a>
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

      it("shares context across multiple tracked elements", async () => {
        application = await setupController(`
          <div data-controller="click-tracker"
               data-click-tracker-page-value="missing_results"
               data-context-jobs-already-added="1">
            <a id="link1" href="#tips" data-action="click->click-tracker#track" data-element-name="search_tips">Tips</a>
            <a id="link2" href="#other" data-action="click->click-tracker#track" data-element-name="other_ways">Other</a>
          </div>
        `)

        document.getElementById("link1").click()
        expect(trackUserAction).toHaveBeenCalledWith(
          "ApplicantClickedElement",
          expect.objectContaining({
            "click.element_name": "search_tips",
            "click_context.jobs_already_added": 1,
          })
        )

        vi.resetAllMocks()

        document.getElementById("link2").click()
        expect(trackUserAction).toHaveBeenCalledWith(
          "ApplicantClickedElement",
          expect.objectContaining({
            "click.element_name": "other_ways",
            "click_context.jobs_already_added": 1,
          })
        )
      })
    })
  })
})
