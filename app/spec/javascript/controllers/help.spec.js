import { describe, it, expect, beforeEach, afterEach } from "vitest"
import { Application } from "@hotwired/stimulus"
import HelpController from "@js/controllers/help.js"
import { trackUserAction } from "@js/utilities/api"

// Mirrors @hotwired/turbo's real <turbo-frame> `src` accessor (confirmed by
// reading its source): a falsy assignment clears the `src` attribute
// entirely instead of navigating anywhere.
function stubTurboFrame(id, initialSrc) {
  const frame = document.createElement("div")
  frame.id = id
  Object.defineProperty(frame, "src", {
    get() {
      return this.getAttribute("src")
    },
    set(value) {
      if (value) {
        this.setAttribute("src", value)
      } else {
        this.removeAttribute("src")
      }
    },
  })
  if (initialSrc) frame.src = initialSrc
  return frame
}

async function setupController(html) {
  document.body.innerHTML = html
  const application = Application.start()
  application.register("help", HelpController)
  await new Promise((resolve) => setTimeout(resolve, 0))
  return application
}

// MutationObserver callbacks are queued as microtasks; a couple of resolved
// promise ticks is enough to let them flush before asserting.
async function flushMutations() {
  await Promise.resolve()
  await Promise.resolve()
}

describe("help_controller", () => {
  let application
  let frame

  beforeEach(() => {
    // Simulates having previously navigated to a topic before closing.
    frame = stubTurboFrame("help_modal_content", "/help/username")
  })

  afterEach(() => {
    application?.stop()
    document.body.innerHTML = ""
  })

  describe("handleClick", () => {
    it("tracks the open event with the trigger's data-source", async () => {
      application = await setupController(`
        <div class="usa-modal-wrapper is-visible">
          <div id="help-modal" data-controller="help" data-help-url="/help">
            <div data-help-target="content"></div>
          </div>
        </div>
        <a href="#help-modal" data-source="banner">Help</a>
      `)
      document.querySelector("[data-help-target='content']").appendChild(frame)

      document.querySelector("a[href='#help-modal']").click()

      expect(trackUserAction).toHaveBeenCalledWith("ApplicantOpenedHelpModal", { source: "banner" })
    })

    it("ignores clicks on elements unrelated to the help modal trigger", async () => {
      application = await setupController(`
        <div class="usa-modal-wrapper is-visible">
          <div id="help-modal" data-controller="help" data-help-url="/help">
            <div data-help-target="content"></div>
          </div>
        </div>
        <a href="#unrelated">Somewhere else</a>
      `)
      document.querySelector("[data-help-target='content']").appendChild(frame)

      document.querySelector("a[href='#unrelated']").click()

      expect(trackUserAction).not.toHaveBeenCalled()
    })
  })

  describe("closing the modal", () => {
    it("resets the frame back to the topic list once the modal's wrapper loses is-visible", async () => {
      application = await setupController(`
        <div class="usa-modal-wrapper is-visible">
          <div id="help-modal" data-controller="help" data-help-url="/help">
            <div data-help-target="content"></div>
          </div>
        </div>
      `)
      document.querySelector("[data-help-target='content']").appendChild(frame)
      const wrapper = document.querySelector(".usa-modal-wrapper")

      wrapper.classList.remove("is-visible")
      wrapper.classList.add("is-hidden")
      await flushMutations()

      expect(frame.getAttribute("src")).toBe("/help")
    })

    it("does not reset while the modal is still open", async () => {
      application = await setupController(`
        <div class="usa-modal-wrapper is-visible">
          <div id="help-modal" data-controller="help" data-help-url="/help">
            <div data-help-target="content"></div>
          </div>
        </div>
      `)
      document.querySelector("[data-help-target='content']").appendChild(frame)
      const wrapper = document.querySelector(".usa-modal-wrapper")

      // An unrelated class change on the (still-visible) wrapper shouldn't reset anything.
      wrapper.classList.add("some-other-class")
      await flushMutations()

      expect(frame.getAttribute("src")).toBe("/help/username")
    })

    it("ignores visibility changes on unrelated elements", async () => {
      application = await setupController(`
        <div class="usa-modal-wrapper is-visible">
          <div id="help-modal" data-controller="help" data-help-url="/help">
            <div data-help-target="content"></div>
          </div>
        </div>
        <div class="usa-modal-wrapper is-visible" id="other-modal"></div>
      `)
      document.querySelector("[data-help-target='content']").appendChild(frame)

      document.getElementById("other-modal").classList.remove("is-visible")
      await flushMutations()

      expect(frame.getAttribute("src")).toBe("/help/username")
    })
  })
})
