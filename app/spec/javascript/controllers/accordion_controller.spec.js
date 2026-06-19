import { vi, describe, beforeEach, it, expect } from "vitest"
import { Application } from "@hotwired/stimulus"
import AccordionController from "@js/controllers/accordion_controller"

const nextTick = () => new Promise((resolve) => setTimeout(resolve, 0))
describe("AccordionController", () => {
  let application
  let container
  let trigger
  let content

  beforeEach(() => {
    document.body.innerHTML = `
      <div class="usa-accordion"
           data-controller="accordion"
           id="accordion-container"
       >
       <div class="usa-accordion__heading" id="heading-id">
          <button type="button"
                  class="usa-accordion__button"
                  data-accordion-target="trigger"
                  aria-controls="content-id"
                  data-action="click->accordion#setContentExpansion"
                  aria-expanded="false"
          >
            Toggle
          </button>
         </div>
        <div id="content-id"
             class="usa-accordion__content"
             data-accordion-target="content"
             hidden
        >
          <div class="usa-summary-box" role="region" aria-labelledby="heading-id">
            <div class="usa-summary-box__body">
              <div class="usa-summary-box__text">
                Content
              </div>
            </div>
          </div>
        </div>
      </div>
    `
    container = document.getElementById("accordion-container")
    trigger = container.querySelector('[data-accordion-target="trigger"]')
    content = container.querySelector('[data-accordion-target="content"]')

    application = Application.start()
    application.register("accordion", AccordionController)
  })

  afterEach(() => {
    application.stop()
    document.body.innerHTML = ""
    vi.restoreAllMocks()
  })

  it("collapses when collapseContent is called", () => {
    content.hidden = false

    const controller = application.getControllerForElementAndIdentifier(container, "accordion")
    controller.collapseContent()

    expect(content.hidden).toBe(true)
    expect(trigger.getAttribute("aria-expanded")).toBe("false")
  })

  it("clicking the trigger toggles the data-context-clicked-to-open property", async () => {
    expect(trigger.getAttribute("data-context-clicked-to-open")).toBe("true")

    trigger.click()
    await nextTick()
    expect(trigger.getAttribute("data-context-clicked-to-open")).toBe("false")

    trigger.click()
    await nextTick()
    expect(trigger.getAttribute("data-context-clicked-to-open")).toBe("true")
  })
})
