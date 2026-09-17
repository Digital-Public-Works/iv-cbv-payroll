import { describe, it, expect, afterEach } from "vitest"
import {
  rebuildHelpModalFocusTrap,
  detachHelpModalFocusTrap,
} from "@js/utilities/helpModalFocusTrap"

// Mirrors the DOM usa-modal builds: a .usa-modal container (tabindex="-1",
// per USWDS's own setup) wrapping the swappable pane content and the close
// button, inside a .usa-modal-wrapper.
function buildOpenModal(focusableLabels) {
  const wrapper = document.createElement("div")
  wrapper.className = "usa-modal-wrapper is-visible"

  const usaModal = document.createElement("div")
  usaModal.className = "usa-modal"
  usaModal.setAttribute("tabindex", "-1")

  const content = document.createElement("div")
  content.className = "usa-modal__body"

  const heading = document.createElement("h2")
  heading.id = "help-modal-heading"
  content.appendChild(heading)

  const buttons = focusableLabels.map((label) => {
    const button = document.createElement("button")
    button.textContent = label
    content.appendChild(button)
    return button
  })

  const closeButton = document.createElement("button")
  closeButton.setAttribute("data-close-modal", "")
  closeButton.textContent = "Close"

  usaModal.append(content, closeButton)
  wrapper.appendChild(usaModal)
  document.body.appendChild(wrapper)

  return { wrapper, usaModal, content, heading, buttons, closeButton }
}

function pressTab(activeElement, { shiftKey = false } = {}) {
  activeElement.focus()
  const event = new window.KeyboardEvent("keydown", {
    key: "Tab",
    code: "Tab",
    shiftKey,
    bubbles: true,
    cancelable: true,
  })
  document.body.dispatchEvent(event)
  return event
}

// Counts document.body's own "keydown" listener add/remove calls, so tests
// can assert on the trap's actual attach/detach lifecycle directly - this is
// exactly the signal that exposed the real bug (a leaked listener after the
// modal closed, from reading/writing a *different* module instance's shared
// "modal" singleton than the one actually driving the page). See
// helpModalFocusTrap.js's module comment for the full story.
function countBodyKeydownListeners() {
  let added = 0
  let removed = 0
  const target = document.body
  const originalAdd = target.addEventListener.bind(target)
  const originalRemove = target.removeEventListener.bind(target)
  target.addEventListener = (type, ...rest) => {
    if (type === "keydown") added++
    return originalAdd(type, ...rest)
  }
  target.removeEventListener = (type, ...rest) => {
    if (type === "keydown") removed++
    return originalRemove(type, ...rest)
  }
  return {
    counts: () => ({ added, removed, net: added - removed }),
    restore: () => {
      target.addEventListener = originalAdd
      target.removeEventListener = originalRemove
    },
  }
}

describe("rebuildHelpModalFocusTrap", () => {
  afterEach(() => {
    detachHelpModalFocusTrap()
    document.body.innerHTML = ""
  })

  it("no-ops when the modal isn't open (no .is-visible wrapper)", () => {
    const wrapper = document.createElement("div")
    wrapper.className = "usa-modal-wrapper" // not is-visible
    const content = document.createElement("div")
    wrapper.appendChild(content)
    document.body.appendChild(wrapper)

    const listeners = countBodyKeydownListeners()
    const result = rebuildHelpModalFocusTrap(content)

    expect(result).toBeNull()
    expect(listeners.counts().added).toBe(0)
    listeners.restore()
  })

  it("rebuilds the trap so Tab/Shift+Tab respect the DOM after a content swap", () => {
    const { content, closeButton, buttons } = buildOpenModal(["Go Back"])

    // Simulate the trap this module itself built when the modal first opened,
    // against the pre-swap ("Go Back" detail view) content.
    rebuildHelpModalFocusTrap(content)

    // Simulate the Turbo Frame swap back to the topic list: different elements entirely.
    buttons[0].remove()
    const usernameLink = document.createElement("a")
    usernameLink.href = "#"
    usernameLink.textContent = "Username"
    content.appendChild(usernameLink)

    rebuildHelpModalFocusTrap(content)

    // Tabbing forward from Close (the last stop) should now wrap to the *new*
    // first stop (the username link), not no-op on a detached stale node -
    // this is the exact "stuck on Close" symptom from the original bug report.
    pressTab(closeButton)
    expect(document.activeElement).toBe(usernameLink)

    // Shift+Tab from the (new) first stop should wrap back to Close, proving
    // the trap's boundaries were recomputed against the live DOM in both directions.
    pressTab(usernameLink, { shiftKey: true })
    expect(document.activeElement).toBe(closeButton)
  })

  it("moves focus to the modal container, not into the swapped content", () => {
    const { content, usaModal } = buildOpenModal(["Go Back"])
    rebuildHelpModalFocusTrap(content)

    rebuildHelpModalFocusTrap(content)

    // Regression check: this previously landed on "Go Back" (the first
    // focusable element) or the pane heading. Neither is right - parking
    // focus on a piece of content anchors a screen reader's virtual cursor
    // there. Focus should land on the modal container itself, matching
    // usa-modal's own open behavior.
    expect(document.activeElement).toBe(usaModal)
  })

  it("detaches the previous trap's listener instead of stacking a second one", () => {
    const { content, closeButton, buttons } = buildOpenModal(["Go Back"])
    const listeners = countBodyKeydownListeners()

    rebuildHelpModalFocusTrap(content)
    rebuildHelpModalFocusTrap(content) // simulates a second content swap with no DOM change

    // Exactly one net keydown listener should be attached - not two stacked ones.
    expect(listeners.counts().net).toBe(1)
    listeners.restore()

    pressTab(closeButton)
    expect(document.activeElement).toBe(buttons[0])
  })
})

describe("detachHelpModalFocusTrap", () => {
  afterEach(() => {
    detachHelpModalFocusTrap()
    document.body.innerHTML = ""
  })

  it("removes the active trap's keydown listener", () => {
    const { content, closeButton } = buildOpenModal(["Go Back"])
    rebuildHelpModalFocusTrap(content)

    const listeners = countBodyKeydownListeners()
    detachHelpModalFocusTrap()
    expect(listeners.counts()).toEqual({ added: 0, removed: 1, net: -1 })
    listeners.restore()

    // Once detached, Tab/Shift+Tab should no longer be intercepted at all.
    closeButton.focus()
    const event = pressTab(closeButton)
    expect(event.defaultPrevented).toBe(false)
  })

  it("is a safe no-op when there is no active trap", () => {
    const listeners = countBodyKeydownListeners()

    expect(() => detachHelpModalFocusTrap()).not.toThrow()
    expect(listeners.counts()).toEqual({ added: 0, removed: 0, net: 0 })
    listeners.restore()
  })
})
