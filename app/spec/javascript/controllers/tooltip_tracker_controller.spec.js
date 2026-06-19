import { vi, describe, afterEach, it, expect } from "vitest"
import { Application } from "@hotwired/stimulus"
import TooltipTrackerController from "@js/controllers/employer_search_tooltip_tracker_controller.js"
import { trackUserAction } from "@js/utilities/api.js"

vi.mock("@js/utilities/api", () => ({
  trackUserAction: vi.fn(),
}))

async function setupController(html) {
  document.body.innerHTML = html
  const application = Application.start()
  application.register("tooltip-tracker", TooltipTrackerController)
  await new Promise((resolve) => setTimeout(resolve, 0))
  
  return application
}

describe("tooltip_tracker_controller", () => {
  let application
  
  afterEach(() => {
    application?.stop()
    document.body.innerHTML = ""
    vi.resetAllMocks()
  })
  
  it("tracks ApplicantClickedSearchBarTooltip events on mouseenter", async () => {
    application = await setupController(`
      <button id="tooltip-btn"
          data-controller="tooltip-tracker"
          data-action="mouseenter->tooltip-tracker#track">
          Test Button
      </button>
      `)
  
    document.getElementById("tooltip-btn").dispatchEvent(new Event("mouseenter"))
    expect(trackUserAction).toHaveBeenCalledTimes(1)
    expect(trackUserAction).toHaveBeenCalledWith("ApplicantClickedSearchBarTooltip")
  })
  
  it("tracks ApplicantClickedSearchBarTooltip events on focus", async () => {
    application = await setupController(`
      <button id="tooltip-btn"
          data-controller="tooltip-tracker"
          data-action="focus->tooltip-tracker#track">
          Test Button
      </button>
      `)
  
    document.getElementById("tooltip-btn").dispatchEvent(new Event("focus"))
    expect(trackUserAction).toHaveBeenCalledTimes(1)
    expect(trackUserAction).toHaveBeenCalledWith("ApplicantClickedSearchBarTooltip")
  })
  
  it("tracks only tracks once across many events", async () => {
    application = await setupController(`
      <button id="tooltip-btn"
          data-controller="tooltip-tracker"
          data-action="mouseenter->tooltip-tracker#track">
          Test Button
      </button>
      `)
  
    const btn = document.getElementById("tooltip-btn")
    btn.dispatchEvent(new Event("mouseenter"))
    btn.dispatchEvent(new Event("focus"))
    btn.dispatchEvent(new Event("mouseenter"))
    btn.dispatchEvent(new Event("mouseenter"))
    expect(trackUserAction).toHaveBeenCalledTimes(1)
    expect(trackUserAction).toHaveBeenCalledWith("ApplicantClickedSearchBarTooltip")
  })
})