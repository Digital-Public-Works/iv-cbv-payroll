import { describe, beforeEach, afterEach, it, expect, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import CharacterCountController from "@js/controllers/cbv/character_count_controller"

describe("CharacterCountController", () => {
  let application
  let container
  let form
  let input
  let message
  let srMessage
  let submitButton

  const setValue = (value) => {
    input.value = value
    input.dispatchEvent(new Event("input"))
  }

  const dispatchSubmit = () => {
    const event = new Event("submit", { bubbles: true, cancelable: true })
    form.dispatchEvent(event)
    return event
  }

  beforeEach(() => {
    container = document.createElement("div")
    container.setAttribute("data-controller", "character-count")
    container.setAttribute("data-character-count-maxlength-value", "1000")
    container.setAttribute(
      "data-character-count-over-limit-text-value",
      "{count} characters over limit."
    )
    container.setAttribute(
      "data-character-count-shorten-text-value",
      "Please make your comment shorter."
    )

    form = document.createElement("form")
    form.setAttribute("data-action", "submit->character-count#guardSubmit")

    input = document.createElement("textarea")
    input.setAttribute("data-character-count-target", "input")
    input.setAttribute("data-action", "input->character-count#update")

    message = document.createElement("div")
    message.setAttribute("data-character-count-target", "message")

    srMessage = document.createElement("div")
    srMessage.setAttribute("data-character-count-target", "srMessage")

    submitButton = document.createElement("input")
    submitButton.type = "submit"
    submitButton.setAttribute("data-character-count-target", "submitButton")

    form.appendChild(input)
    form.appendChild(message)
    form.appendChild(srMessage)
    form.appendChild(submitButton)
    container.appendChild(form)
    document.body.appendChild(container)

    application = Application.start()
    application.register("character-count", CharacterCountController)
  })

  afterEach(() => {
    application.stop()
    document.body.innerHTML = ""
    vi.restoreAllMocks()
  })

  it("shows an initial count, enables the submit button, and keeps it focusable", () => {
    expect(message.textContent).toBe("0/1000")
    expect(srMessage.textContent).toBe("")
    expect(submitButton.disabled).toBe(false)
    expect(submitButton.getAttribute("aria-disabled")).toBe("false")

    expect(dispatchSubmit().defaultPrevented).toBe(false)
  })

  describe("when typing under the limit", () => {
    beforeEach(() => {
      setValue("a".repeat(500))
    })

    it("updates the visible counter without announcing anything, and allows submission", () => {
      expect(message.textContent).toBe("500/1000")
      expect(srMessage.textContent).toBe("")
      expect(input.hasAttribute("aria-invalid")).toBe(false)
      expect(submitButton.disabled).toBe(false)
      expect(submitButton.getAttribute("aria-disabled")).toBe("false")

      expect(dispatchSubmit().defaultPrevented).toBe(false)
    })
  })

  describe("when typing over the limit", () => {
    beforeEach(() => {
      setValue("a".repeat(1050))
    })

    it("shows the combined error message and marks the field invalid", () => {
      const expected = "50 characters over limit. Please make your comment shorter."

      expect(message.textContent).toBe(expected)
      expect(srMessage.textContent).toBe(expected)
      expect(input.getAttribute("aria-invalid")).toBe("true")
    })

    it("marks the submit button aria-disabled but keeps it focusable (not the native disabled attribute)", () => {
      expect(submitButton.disabled).toBe(false)
      expect(submitButton.getAttribute("aria-disabled")).toBe("true")
      expect(submitButton.tabIndex).not.toBe(-1)
    })

    it("blocks form submission", () => {
      expect(dispatchSubmit().defaultPrevented).toBe(true)
    })

    describe("and then typing back under the limit", () => {
      beforeEach(() => {
        setValue("a".repeat(200))
      })

      it("clears the error state, re-enables the submit button, and allows submission", () => {
        expect(message.textContent).toBe("200/1000")
        expect(srMessage.textContent).toBe("")
        expect(input.hasAttribute("aria-invalid")).toBe(false)
        expect(submitButton.disabled).toBe(false)
        expect(submitButton.getAttribute("aria-disabled")).toBe("false")

        expect(dispatchSubmit().defaultPrevented).toBe(false)
      })
    })
  })
})
