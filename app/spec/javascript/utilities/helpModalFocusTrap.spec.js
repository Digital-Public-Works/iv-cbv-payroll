import { describe, it, expect, afterEach, vi } from "vitest"
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

// Counts document.body's own "keydown" listener add/remove calls (regardless
// of capture/bubble phase), so tests can assert on the guard's actual
// attach/detach lifecycle directly.
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

function installStaleUswdsTrap(staleFirst, staleLast, staleFocusable) {
  const listener = vi.fn((event) => {
    if (event.key !== "Tab") return
    if (event.shiftKey) {
      if (document.activeElement === staleFirst) {
        event.preventDefault()
        staleLast.focus()
      } else if (!staleFocusable.includes(document.activeElement)) {
        event.preventDefault()
        staleFirst.focus() // a detached node in practice; focusing it silently no-ops
      }
    } else if (document.activeElement === staleLast) {
      event.preventDefault()
      staleFirst.focus()
    }
  })
  document.body.addEventListener("keydown", listener)
  return listener
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

  it("respects the live DOM after a content swap, with no rebuild call needed", () => {
    const { content, closeButton, buttons } = buildOpenModal(["Go Back"])
    rebuildHelpModalFocusTrap(content)

    // Simulate the Turbo Frame swap back to the topic list - different
    // elements entirely, and critically, no second rebuild call: focusable
    // elements are recomputed fresh from the DOM on every keypress, so
    // nothing needs to be told about the swap for Tab/Shift+Tab to stay correct.
    buttons[0].remove()
    const usernameLink = document.createElement("a")
    usernameLink.href = "#"
    usernameLink.textContent = "Username"
    content.appendChild(usernameLink)

    // Tabbing forward from Close (the last stop) should wrap to the *new*
    // first stop (the username link)
    pressTab(closeButton)
    expect(document.activeElement).toBe(usernameLink)

    // Shift+Tab from the (new) first stop should wrap back to Close.
    pressTab(usernameLink, { shiftKey: true })
    expect(document.activeElement).toBe(closeButton)
  })

  it("moves focus to the modal container, not into the swapped content", () => {
    const { content, usaModal } = buildOpenModal(["Go Back"])
    rebuildHelpModalFocusTrap(content)

    // Regression check: this previously landed on "Go Back" (the first
    // focusable element) or the pane heading. Neither is right - parking
    // focus on a piece of content anchors a screen reader's virtual cursor
    // there. Focus should land on the modal container itself, matching
    // usa-modal's own open behavior.
    expect(document.activeElement).toBe(usaModal)
  })

  it("does not attach a second listener on repeated rebuilds", () => {
    const { content } = buildOpenModal(["Go Back"])
    const listeners = countBodyKeydownListeners()

    rebuildHelpModalFocusTrap(content)
    rebuildHelpModalFocusTrap(content) // simulates a second content swap

    expect(listeners.counts()).toEqual({ added: 1, removed: 0, net: 1 })
    listeners.restore()
  })

  describe("shielding against a stale trap from another module instance", () => {
    it("still wraps correctly from the true first/last elements, and the stale trap never runs", () => {
      const { content, closeButton, buttons } = buildOpenModal(["Go Back"])
      // A stale trap captured against content that no longer exists (a
      // detached node stand-in for "Go Back", to mimic the real scenario
      // where USWDS's own trap's boundaries point at removed elements).
      const staleDetachedFirst = document.createElement("button")
      const staleTrap = installStaleUswdsTrap(staleDetachedFirst, staleDetachedFirst, [
        staleDetachedFirst,
      ])

      buttons[0].remove()
      const usernameLink = document.createElement("a")
      usernameLink.href = "#"
      usernameLink.textContent = "Username"
      content.appendChild(usernameLink)

      rebuildHelpModalFocusTrap(content)

      pressTab(closeButton) // Tab forward from the true last element
      expect(document.activeElement).toBe(usernameLink)
      expect(staleTrap).not.toHaveBeenCalled()

      pressTab(usernameLink, { shiftKey: true }) // Shift+Tab from the true first element
      expect(document.activeElement).toBe(closeButton)
      expect(staleTrap).not.toHaveBeenCalled()
    })

    it("passes Shift+Tab through to native handling from a middle element, without the stale trap swallowing it", () => {
      const { content, buttons } = buildOpenModal(["Go Back"])
      const staleDetachedFirst = document.createElement("button")
      const staleTrap = installStaleUswdsTrap(staleDetachedFirst, staleDetachedFirst, [
        staleDetachedFirst,
      ])

      buttons[0].remove()
      const usernameLink = document.createElement("a")
      usernameLink.href = "#"
      usernameLink.textContent = "Username"
      content.appendChild(usernameLink)
      const passwordLink = document.createElement("a")
      passwordLink.href = "#"
      passwordLink.textContent = "Password"
      content.appendChild(passwordLink)

      rebuildHelpModalFocusTrap(content)

      const event = pressTab(passwordLink, { shiftKey: true })
      expect(event.defaultPrevented).toBe(false)
      expect(staleTrap).not.toHaveBeenCalled()
    })
  })
})

describe("detachHelpModalFocusTrap", () => {
  afterEach(() => {
    detachHelpModalFocusTrap()
    document.body.innerHTML = ""
  })

  it("removes the guard's keydown listener", () => {
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

  it("is a safe no-op when there is no active guard", () => {
    const listeners = countBodyKeydownListeners()

    expect(() => detachHelpModalFocusTrap()).not.toThrow()
    expect(listeners.counts()).toEqual({ added: 0, removed: 0, net: 0 })
    listeners.restore()
  })
})
