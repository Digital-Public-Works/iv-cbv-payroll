import { vi, describe, beforeEach, it, expect } from "vitest"
import { Application } from "@hotwired/stimulus"
import AccordionController from "@js/controllers/accordion_controller"

describe("AccordionController", () => {
  let application
  let container
  let trigger
  let content
  const createClickEvent = () => {
    const event = new MouseEvent("click", { bubbles: true, cancelable: true })
    vi.spyOn(event, "preventDefault")
    return event
  }

  beforeEach(() => {
    container = document.createElement("div")
    container.setAttribute("data-controller", "accordion")

    trigger = document.createElement("button")
    trigger.setAttribute("data-accordion-target", "trigger")
    trigger.setAttribute("data-action", "click->accordion#setContentExpansion")
    trigger.setAttribute("aria-expanded", "false")

    content = document.createElement("div")
    content.setAttribute("data-accordion-target", "content")
    content.hidden = true
    content.classList.add("hidden")

    container.appendChild(trigger)
    container.appendChild(content)
    document.body.appendChild(container)

    application = Application.start()
    application.register("accordion", AccordionController)
  })

  afterEach(() => {
    application.stop()
    document.body.innerHTML = ""
    vi.restoreAllMocks()
  })

  it("toggles the content when the trigger is clicked", () => {
    expect(content.hidden).toBe(true)

    trigger.click()

    expect(content.hidden).toBe(false)
    expect(trigger.getAttribute("aria-expanded")).toBe("true")

    trigger.click()
    expect(content.hidden).toBe(true)
    expect(trigger.getAttribute("aria-expanded")).toBe("false")
  })
})
