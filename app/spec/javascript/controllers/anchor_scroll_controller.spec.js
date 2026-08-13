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

  it("scrolls to and focuses the target on click", async () => {
    // jsdom does not implement scrollIntoView, so stub it on the prototype.
    const scrollIntoView = vi
      .spyOn(Element.prototype, "scrollIntoView")
      .mockImplementation(() => {})

    application = await setupController(`
      <input id="query" type="search" />
      <button href="#query"
          data-controller="anchor-scroll"
          data-action="click->anchor-scroll#scroll">
          Back to top
      </button>
    `)

    document.querySelector("button").click()

    expect(scrollIntoView).toHaveBeenCalledWith({ behavior: "smooth" })
    expect(document.activeElement).toBe(document.getElementById("query"))
  })

  it("ignores non-hash links", async () => {
    const scrollIntoView = vi
      .spyOn(Element.prototype, "scrollIntoView")
      .mockImplementation(() => {})

    application = await setupController(`
      <a href="/somewhere"
          data-controller="anchor-scroll"
          data-action="click->anchor-scroll#scroll">
          Elsewhere
      </a>
    `)

    document.querySelector("a").dispatchEvent(new Event("click", { bubbles: true }))

    expect(scrollIntoView).not.toHaveBeenCalled()
  })
})
