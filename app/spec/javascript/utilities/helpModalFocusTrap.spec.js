import { describe, it, expect, afterEach } from "vitest"
import { rebuildHelpModalFocusTrap } from "@js/utilities/helpModalFocusTrap"
import FocusTrap from "@uswds/uswds/uswds-core/src/js/utils/focus-trap.js"
import components from "@uswds/uswds/src/js/components"

const modal = components.modal

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

describe("rebuildHelpModalFocusTrap", () => {
  afterEach(() => {
    if (modal.focusTrap) {
      modal.focusTrap.off()
      modal.focusTrap = null
    }
    document.body.innerHTML = ""
  })

  it("no-ops when the modal isn't open (no .is-visible wrapper)", () => {
    const wrapper = document.createElement("div")
    wrapper.className = "usa-modal-wrapper" // not is-visible
    const content = document.createElement("div")
    wrapper.appendChild(content)
    document.body.appendChild(wrapper)

    const result = rebuildHelpModalFocusTrap(content)

    expect(result).toBeNull()
    expect(modal.focusTrap).toBeFalsy()
  })

  it("rebuilds the trap so Tab/Shift+Tab respect the DOM after a content swap", () => {
    const { content, closeButton, buttons } = buildOpenModal(["Go Back"])

    // Simulate usa-modal's own toggleModal building the initial trap on open,
    // against the pre-swap ("Go Back" detail view) content.
    const targetModal = content.closest(".usa-modal-wrapper.is-visible")
    modal.focusTrap = FocusTrap(targetModal, { Escape: () => {} })
    modal.focusTrap.update(true)

    // Simulate the Turbo Frame swap back to the topic list: different elements entirely.
    buttons[0].remove()
    const usernameLink = document.createElement("a")
    usernameLink.href = "#"
    usernameLink.textContent = "Username"
    content.appendChild(usernameLink)

    rebuildHelpModalFocusTrap(content)

    // Tabbing forward from Close (the last stop) should now wrap to the *new*
    // first stop (the username link), not no-op on a detached stale node -
    // this is the exact "stuck on Close" symptom from the bug report.
    pressTab(closeButton)
    expect(document.activeElement).toBe(usernameLink)

    // Shift+Tab from the (new) first stop should wrap back to Close, proving
    // the trap's boundaries were recomputed against the live DOM in both directions.
    pressTab(usernameLink, { shiftKey: true })
    expect(document.activeElement).toBe(closeButton)
  })

  it("moves focus to the modal container, not into the swapped content", () => {
    const { content, usaModal } = buildOpenModal(["Go Back"])
    const targetModal = content.closest(".usa-modal-wrapper.is-visible")
    modal.focusTrap = FocusTrap(targetModal, { Escape: () => {} })
    modal.focusTrap.update(true)

    rebuildHelpModalFocusTrap(content)

    // Regression check: previously this landed on "Go Back" (the first
    // focusable element, because update(true) ran FocusTrap's init()), then
    // on the pane heading. Neither is right - parking focus on a piece of
    // content anchors a screen reader's virtual cursor there. Focus should
    // land on the modal container itself, matching usa-modal's own open behavior.
    expect(document.activeElement).toBe(usaModal)
  })

  it("detaches the previous trap's listener instead of stacking a second one", () => {
    const { content, closeButton, buttons } = buildOpenModal(["Go Back"])
    const targetModal = content.closest(".usa-modal-wrapper.is-visible")

    modal.focusTrap = FocusTrap(targetModal, { Escape: () => {} })
    modal.focusTrap.update(true)
    const firstTrap = modal.focusTrap

    rebuildHelpModalFocusTrap(content)

    expect(modal.focusTrap).not.toBe(firstTrap)

    // If the old listener leaked, tabAhead's stale preventDefault would still
    // fire alongside the new one; asserting a single, correct focus target
    // after tabbing is enough to show only the new trap is active.
    pressTab(closeButton)
    expect(document.activeElement).toBe(buttons[0])
  })

  it("still closes the modal on Escape after being rebuilt", () => {
    const { content } = buildOpenModal(["Go Back"])
    const targetModal = content.closest(".usa-modal-wrapper.is-visible")
    modal.focusTrap = FocusTrap(targetModal, { Escape: () => {} })
    modal.focusTrap.update(true)

    rebuildHelpModalFocusTrap(content)

    const originalToggleModal = modal.toggleModal
    let closed = false
    modal.toggleModal = () => {
      closed = true
    }

    try {
      const escapeEvent = new window.KeyboardEvent("keydown", {
        key: "Escape",
        code: "Escape",
        bubbles: true,
        cancelable: true,
      })
      document.body.dispatchEvent(escapeEvent)

      expect(closed).toBe(true)
    } finally {
      modal.toggleModal = originalToggleModal
    }
  })
})
