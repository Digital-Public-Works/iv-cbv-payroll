import { describe, beforeEach, afterEach, it, expect } from "vitest"
import { Application } from "@hotwired/stimulus"
import SpinnerSyncController from "@js/controllers/spinner_sync_controller"

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0))

describe("SpinnerSyncController", () => {
  let application
  let animations

  beforeEach(() => {
    document.body.innerHTML = ""
    animations = [{ startTime: 1234 }, { startTime: 567 }]
    // jsdom doesn't implement the Web Animations API.
    window.Element.prototype.getAnimations = function () {
      return this.dataset.controller === "spinner-sync" ? animations : []
    }
    application = Application.start()
    application.register("spinner-sync", SpinnerSyncController)
  })

  afterEach(() => {
    application.stop()
    delete window.Element.prototype.getAnimations
  })

  it("pins each animation to the document timeline origin so spinners share a phase", async () => {
    document.body.innerHTML = `<svg data-controller="spinner-sync"></svg>`
    await flushPromises()

    expect(animations.map((animation) => animation.startTime)).toEqual([0, 0])
  })

  it("does nothing when the Web Animations API is unavailable", async () => {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
    svg.setAttribute("data-controller", "spinner-sync")
    svg.getAnimations = undefined
    document.body.replaceChildren(svg)
    await flushPromises()

    expect(animations.map((animation) => animation.startTime)).toEqual([1234, 567])
  })
})
