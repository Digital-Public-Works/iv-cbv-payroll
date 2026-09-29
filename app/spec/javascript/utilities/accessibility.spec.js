import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import {
  toggleErrorIds,
  updateAriaLiveRegion,
  activateWithSpace,
} from "@js/utilities/accessibility"

describe("toggleErrorIds", () => {
  let target

  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("adds the id to aria-describedby when there's an error and it isn't already present", () => {
    target = document.createElement("input")
    target.setAttribute("aria-describedby", "company_examples")

    toggleErrorIds(target, true, "query_error_message")

    expect(target.getAttribute("aria-describedby")).toBe("query_error_message company_examples")
  })

  it("does not duplicate the id when called again while the error is already present", () => {
    target = document.createElement("input")
    target.setAttribute("aria-describedby", "company_examples")

    toggleErrorIds(target, true, "query_error_message")
    toggleErrorIds(target, true, "query_error_message")

    expect(target.getAttribute("aria-describedby")).toBe("query_error_message company_examples")
  })

  it("removes the id and trims whitespace when the error is cleared", () => {
    target = document.createElement("input")
    target.setAttribute("aria-describedby", "query_error_message company_examples")

    toggleErrorIds(target, false, "query_error_message")

    expect(target.getAttribute("aria-describedby")).toBe("company_examples")
  })
})

describe("activateWithSpace", () => {
  let element

  beforeEach(() => {
    element = document.createElement("a")
    element.setAttribute("role", "button")
    element.addEventListener("keydown", activateWithSpace)
    document.body.appendChild(element)
  })

  afterEach(() => {
    document.body.innerHTML = ""
  })

  function press(key) {
    const event = new window.KeyboardEvent("keydown", { key, cancelable: true })
    element.dispatchEvent(event)
    return event
  }

  it("activates the element on a Space keydown", () => {
    const clickSpy = vi.fn()
    element.addEventListener("click", clickSpy)

    const event = press(" ")

    expect(clickSpy).toHaveBeenCalled()
    expect(event.defaultPrevented).toBe(true)
  })

  it("activates the element on a Spacebar keydown (older browsers)", () => {
    const clickSpy = vi.fn()
    element.addEventListener("click", clickSpy)

    const event = press("Spacebar")

    expect(clickSpy).toHaveBeenCalled()
    expect(event.defaultPrevented).toBe(true)
  })

  it("does nothing for other keys, leaving native activation (e.g. Enter) to the browser", () => {
    const clickSpy = vi.fn()
    element.addEventListener("click", clickSpy)

    const event = press("Enter")

    expect(clickSpy).not.toHaveBeenCalled()
    expect(event.defaultPrevented).toBe(false)
  })
})

describe("updateAriaLiveRegion", () => {
  let liveRegion

  beforeEach(() => {
    liveRegion = document.createElement("div")
    liveRegion.id = "live-announcer"
    document.body.appendChild(liveRegion)
  })

  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("sets the live region's text content", () => {
    updateAriaLiveRegion("Enter letters or numbers")

    expect(liveRegion.textContent).toBe("Enter letters or numbers")
  })

  it("clears prior content when called with no text", () => {
    updateAriaLiveRegion("Enter letters or numbers")
    updateAriaLiveRegion()

    expect(liveRegion.textContent).toBe("")
  })
})
