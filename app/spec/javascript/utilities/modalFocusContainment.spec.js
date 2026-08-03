import { describe, it, expect, afterEach } from "vitest"
import { restoreFocusTo } from "@js/utilities/modalFocusContainment"

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

describe("restoreFocusTo", () => {
  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("focuses the trigger element immediately, with no upfront delay", () => {
    const trigger = document.createElement("button")
    document.body.appendChild(trigger)

    restoreFocusTo(trigger)

    expect(document.activeElement).toBe(trigger)
  })

  it("falls back to the fallback element when the trigger was removed", () => {
    const trigger = document.createElement("button")
    // Mirrors the real page heading, which needs tabindex="-1" to be
    // programmatically focusable despite not being an interactive element.
    const fallback = document.createElement("h1")
    fallback.setAttribute("tabindex", "-1")
    document.body.appendChild(fallback)
    // trigger deliberately never attached, simulating DOM churn while the modal was open

    restoreFocusTo(trigger, fallback)

    expect(document.activeElement).toBe(fallback)
  })

  it("falls back to document.body when neither trigger nor fallback is available", () => {
    restoreFocusTo(undefined, undefined)

    expect(document.activeElement).toBe(document.body)
  })

  it("reclaims focus if it falls back to document.body shortly afterward", async () => {
    const trigger = document.createElement("button")
    document.body.appendChild(trigger)

    restoreFocusTo(trigger)
    trigger.blur() // nothing else takes focus, so activeElement falls back to <body>
    expect(document.activeElement).toBe(document.body)

    await wait(150)

    expect(document.activeElement).toBe(trigger)
  })

  it("keeps correcting if focus falls back to document.body more than once", async () => {
    const trigger = document.createElement("button")
    document.body.appendChild(trigger)

    restoreFocusTo(trigger)
    trigger.blur()
    await wait(150)
    expect(document.activeElement).toBe(trigger)

    trigger.blur()
    await wait(150)

    expect(document.activeElement).toBe(trigger)
  })

  it("does not fight focus that moves to a different real element", async () => {
    const trigger = document.createElement("button")
    const other = document.createElement("button")
    document.body.append(trigger, other)

    restoreFocusTo(trigger)
    other.focus()

    await wait(150)

    expect(document.activeElement).toBe(other)
  })

  it("no longer reclaims focus once the guard window has elapsed", async () => {
    const trigger = document.createElement("button")
    document.body.appendChild(trigger)

    restoreFocusTo(trigger)
    await wait(2100) // guard window (2000ms) has elapsed with no focus change

    trigger.blur()
    await wait(150)

    expect(document.activeElement).toBe(document.body)
  }, 10000)
})
