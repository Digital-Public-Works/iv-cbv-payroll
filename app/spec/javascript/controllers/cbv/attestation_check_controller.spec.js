import { vi, describe, beforeEach, it, expect } from "vitest"
import { Application } from "@hotwired/stimulus"
import AttestationCheckController from "@js/controllers/cbv/attestation_check_controller"

describe("AttestationCheckController", () => {
  let application
  let container
  let form
  let checkBox
  let submitButton
  const createClickEvent = () => {
    const event = new MouseEvent("click", { bubbles: true, cancelable: true })
    vi.spyOn(event, "preventDefault")
    return event
  }

  beforeEach(() => {
    container = document.createElement("div")
    container.setAttribute("data-controller", "attestation-check")

    form = document.createElement("form")

    checkBox = document.createElement("input")
    checkBox.type = "checkbox"
    checkBox.setAttribute("data-attestation-check-target", "attestationCheckbox")
    checkBox.setAttribute("data-action", "change->attestation-check#setButton")

    submitButton = document.createElement("button")
    submitButton.type = "submit"
    submitButton.setAttribute("data-attestation-check-target", "submitButton")
    submitButton.setAttribute("data-action", "click->attestation-check#submit")

    form.appendChild(checkBox)
    form.appendChild(submitButton)
    container.appendChild(form)
    document.body.appendChild(container)

    application = Application.start()
    application.register("attestation-check", AttestationCheckController)
  })

  afterEach(() => {
    application.stop()
    document.body.innerHTML = ""
    vi.restoreAllMocks()
  })

  it("initially sets button to disabled", () => {
    expect(submitButton.disabled).toBe(true)
    expect(submitButton.getAttribute("aria-disabled")).toBe("true")
  })

  describe("when checkbox is checked", () => {
    beforeEach(() => {
      checkBox.checked = true
      checkBox.dispatchEvent(new Event("change"))
    })

    it("enables the submit button", () => {
      expect(submitButton.disabled).toBe(false)
      expect(submitButton.getAttribute("aria-disabled")).toBe("false")
    })

    it("does not prevent the default action of the button", () => {
      const clickEvent = createClickEvent()
      submitButton.dispatchEvent(clickEvent)

      expect(clickEvent.preventDefault).not.toHaveBeenCalled()
    })
  })

  describe("when checkbox is unchecked", () => {
    beforeEach(() => {
      checkBox.checked = true
      checkBox.dispatchEvent(new Event("change"))

      checkBox.checked = false
      checkBox.dispatchEvent(new Event("change"))
    })

    it("disables the submit button", () => {
      expect(submitButton.disabled).toBe(true)
      expect(submitButton.getAttribute("aria-disabled")).toBe("true")
    })

    it("prevents the default action of the button and focuses on the checkbox", () => {
      const clickEvent = createClickEvent()
      submitButton.dispatchEvent(clickEvent)

      expect(clickEvent.preventDefault).toHaveBeenCalled()
      expect(document.activeElement).toBe(checkBox)
    })
  })
})
