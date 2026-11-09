import { vi, describe, beforeEach, afterEach, it, expect } from "vitest"
import CopyLinkController from "@js/controllers/copy_link_controller"
import { trackUserAction } from "@js/utilities/api"

const flushPromises = () => vi.advanceTimersByTimeAsync(0)

describe("CopyLinkController", () => {
  let input
  let copyButton
  let successButton
  let writeText

  beforeEach(async () => {
    vi.useFakeTimers()
    writeText = vi.fn(() => Promise.resolve())
    Object.defineProperty(navigator, "clipboard", { value: { writeText }, configurable: true })

    document.body.innerHTML = `
      <div data-controller="copy-link">
        <input readonly value="https://example.com/invite" data-copy-link-target="input">
        <button type="button" data-copy-link-target="copyLinkButton" data-action="click->copy-link#copy">
          Copy link
        </button>
        <button type="button" class="invisible" data-copy-link-target="successButton">
          Copied link
        </button>
      </div>
      <a href="#" id="elsewhere">Elsewhere</a>
    `
    input = document.querySelector('[data-copy-link-target="input"]')
    copyButton = document.querySelector('[data-copy-link-target="copyLinkButton"]')
    successButton = document.querySelector('[data-copy-link-target="successButton"]')

    window.Stimulus.register("copy-link", CopyLinkController)
    await flushPromises()
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it("copies the link and tracks the event", async () => {
    copyButton.click()
    await flushPromises()

    expect(writeText).toHaveBeenCalledWith(input.value)
    expect(trackUserAction).toHaveBeenCalledWith("ApplicantCopiedInvitationLink")
  })

  it("moves focus to the success button when the focused copy button is hidden", async () => {
    copyButton.focus()
    copyButton.click()
    await flushPromises()

    expect(copyButton.classList.contains("invisible")).toBe(true)
    expect(successButton.classList.contains("invisible")).toBe(false)
    expect(document.activeElement).toBe(successButton)
  })

  it("returns focus to the copy button when the success state ends", async () => {
    copyButton.focus()
    copyButton.click()
    await flushPromises()

    await vi.advanceTimersByTimeAsync(3000)

    expect(copyButton.classList.contains("invisible")).toBe(false)
    expect(successButton.classList.contains("invisible")).toBe(true)
    expect(document.activeElement).toBe(copyButton)
  })

  it("does not move focus when the copy button was not focused", async () => {
    copyButton.click()
    await flushPromises()

    expect(successButton.classList.contains("invisible")).toBe(false)
    expect(document.activeElement).toBe(document.body)
  })

  it("does not steal focus back if the user has moved on", async () => {
    copyButton.focus()
    copyButton.click()
    await flushPromises()

    const elsewhere = document.getElementById("elsewhere")
    elsewhere.focus()
    await vi.advanceTimersByTimeAsync(3000)

    expect(copyButton.classList.contains("invisible")).toBe(false)
    expect(document.activeElement).toBe(elsewhere)
  })
})
