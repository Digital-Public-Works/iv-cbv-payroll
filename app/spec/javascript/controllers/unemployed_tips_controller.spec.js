import { vi, describe, beforeEach, it, expect } from "vitest"
import { Application } from "@hotwired/stimulus"
import UnemployedTipsController from "@js/controllers/unemployed_tips_controller"
import AccordionController from "@js/controllers/accordion_controller.js"

describe("UnemployedTipsController", () => {
  let application
  let container
  let tipsAccordion
  let accordionTrigger
  let accordionContent

  beforeEach(() => {
    document.body.innerHTML = `
      <div data-controller="unemployed-tips click-tracker"
           data-action="turbo:before-fetch-request@document->unemployed-tips#closeTipsExternal
                     click@document->unemployed-tips#closeTipsExternal"
           id="unemployed-tips-section"
      >
        <div class="usa-accordion"
             data-controller="accordion"
             data-unemployed-tips-target="tipsAccordion"
             id="accordion-container"
        >
         <div class="usa-accordion__heading" id="heading-id">
            <button type="button"
                    class="usa-accordion__button"
                    data-accordion-target="trigger"
                    aria-controls="content-id"
                    data-action="click->accordion#setContentExpansion"
                    aria-expanded="true"
            >
              Toggle
            </button>
           </div>
          <div id="content-id"
               class="usa-accordion__content"
               data-accordion-target="content"
          >
            <div class="usa-summary-box" role="region" aria-labelledby="heading-id">
              <div>
                <button type="button"
                        class="usa-button--unstyled usa-link"
                        data-unemployed-tips-target="closeLink"
                        data-action="click->unemployed-tips#closeTips"
                >
                  Close this message
                </button>
              </div>
             </div>
          </div>
        </div>
      </div>

      <form class="usa-search" id="mock-search-form"></form>

      <div id="popular">
        <button id="mock-employer-button" data-cbv-employer-search-target="employerButton">
          Payment Provider
        </button>
      </div>

    `
    container = document.getElementById("unemployed-tips-section")
    tipsAccordion = container.querySelector('[data-unemployed-tips-target="tipsAccordion"]')
    accordionContent = container.querySelector('[data-accordion-target="content"]')
    accordionTrigger = container.querySelector('[data-accordion-target="trigger"]')

    application = Application.start()
    application.register("accordion", AccordionController)
    application.register("unemployed-tips", UnemployedTipsController)
  })

  afterEach(() => {
    application.stop()
    document.body.innerHTML = ""
    vi.restoreAllMocks()
  })

  it("closes the tips when a search request is initiated", () => {
    expect(accordionTrigger.getAttribute("aria-expanded")).toBe("true")

    const searchForm = document.getElementById("mock-search-form")
    const turboEvent = new CustomEvent("turbo:before-fetch-request", {
      bubbles: true,
      cancelable: true,
    })

    Object.defineProperty(turboEvent, "target", { value: searchForm, enumerable: true })

    document.dispatchEvent(turboEvent)

    expect(accordionTrigger.getAttribute("aria-expanded")).toBe("false")
  })

  it("closes the tips when a turbo frame is loaded when switching from payroll providers to app-based employers", () => {
    expect(accordionTrigger.getAttribute("aria-expanded")).toBe("true")

    const popular_providers = document.getElementById("popular")
    const turboEvent = new CustomEvent("turbo:before-fetch-request", {
      bubbles: true,
      cancelable: true,
    })

    Object.defineProperty(turboEvent, "target", { value: popular_providers, enumerable: true })

    document.dispatchEvent(turboEvent)

    expect(accordionTrigger.getAttribute("aria-expanded")).toBe("false")
  })

  it("closes the tips when an employer button is clicked", () => {
    expect(accordionTrigger.getAttribute("aria-expanded")).toBe("true")

    const employerBtn = document.getElementById("mock-employer-button")
    employerBtn.click()

    expect(accordionTrigger.getAttribute("aria-expanded")).toBe("false")
  })

  it("does not close the tips when clicking elsewhere on the document", () => {
    expect(accordionTrigger.getAttribute("aria-expanded")).toBe("true")

    const randomDiv = document.createElement("div")
    document.body.appendChild(randomDiv)
    randomDiv.click()

    expect(accordionTrigger.getAttribute("aria-expanded")).toBe("true")
  })

  it("closes the accordion when the close link is clicked", () => {
    expect(accordionTrigger.getAttribute("aria-expanded")).toBe("true")
    expect(accordionContent.hasAttribute("hidden")).toBe(false)

    const accordion = application.getControllerForElementAndIdentifier(tipsAccordion, "accordion")
    const collapseSpy = vi.spyOn(accordion, "collapseContent")

    const closeLink = container.querySelector('[data-unemployed-tips-target="closeLink"]')
    closeLink.click()

    expect(collapseSpy).toHaveBeenCalled()

    expect(accordionTrigger.getAttribute("aria-expanded")).toBe("false")
    expect(accordionContent.hasAttribute("hidden")).toBe(true)
  })
})
