import { describe, it, expect, beforeEach, afterEach } from "vitest"
import { toggleErrorIds, updateAriaLiveRegion } from "@js/utilities/accessibility"

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
