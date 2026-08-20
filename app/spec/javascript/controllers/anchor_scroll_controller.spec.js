import { vi, describe, afterEach, it, expect } from "vitest"
import { Application } from "@hotwired/stimulus"
import AnchorScrollController from "@js/controllers/anchor_scroll_controller.js"

async function setupController(html) {
  document.body.innerHTML = html
  const application = Application.start()
  application.register("anchor-scroll", AnchorScrollController)
  await new Promise((resolve) => setTimeout(resolve, 0))

  return application
}

describe("anchor_scroll_controller", () => {
  let application

  afterEach(() => {
    application?.stop()
    document.body.innerHTML = ""
    vi.restoreAllMocks()
  })

  it("smooth-scrolls to and moves focus to the target on click", async () => {
    application = await setupController(`
      <input id="query" type="search" />
      <button href="#query"
          data-controller="anchor-scroll"
          data-action="click->anchor-scroll#scroll">
          Back to top
      </button>
    `)
    const target = document.getElementById("query")
    // jsdom doesn't implement scrollIntoView
    target.scrollIntoView = vi.fn()
    const focusSpy = vi.spyOn(target, "focus")

    document.querySelector("button").click()

    expect(target.scrollIntoView).toHaveBeenCalledWith({ behavior: "smooth" })
    // Focus, not just scroll: keyboard/screen-reader users land on the input.
    expect(focusSpy).toHaveBeenCalledWith({ preventScroll: true })
  })

  it("ignores non-hash links (does not hijack the click)", async () => {
    application = await setupController(`
      <a href="/somewhere"
          data-controller="anchor-scroll"
          data-action="click->anchor-scroll#scroll">
          Elsewhere
      </a>
    `)
    const event = new Event("click", { bubbles: true, cancelable: true })

    document.querySelector("a").dispatchEvent(event)

    expect(event.defaultPrevented).toBe(false)
  })
})
