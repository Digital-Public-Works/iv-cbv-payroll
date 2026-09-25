const FOCUSABLE_SELECTOR =
  'a[href], area[href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), button:not([disabled]), iframe, object, embed, [tabindex="0"], [contenteditable]'

let isListening = false

function getFocusableElements(wrapper) {
  return Array.from(wrapper.querySelectorAll(FOCUSABLE_SELECTOR))
}

function handleKeydown(event) {
  if (event.key !== "Tab") return

  const wrapper = document.querySelector(".usa-modal-wrapper.is-visible")
  if (!wrapper) return

  const focusable = getFocusableElements(wrapper)
  if (focusable.length === 0) return

  event.stopImmediatePropagation()

  const first = focusable[0]
  const last = focusable[focusable.length - 1]
  const active = document.activeElement

  if (event.shiftKey && (active === first || !focusable.includes(active))) {
    event.preventDefault()
    last.focus()
  } else if (!event.shiftKey && active === last) {
    event.preventDefault()
    first.focus()
  }
  // Otherwise: let the browser's native Tab movement proceed - we've
  // already shielded it above, we just don't need to redirect it ourselves.
}

// Call this after any Turbo Frame swap inside the modal (see help.js) to
// restore focus to the modal container. Also ensures the keydown guard
// above is installed (idempotent - safe to call on every swap).
//
// Returns the modal wrapper element if the modal was open, or null if the
// modal wasn't open (nothing to do).
export function rebuildHelpModalFocusTrap(contentEl) {
  const targetModal = contentEl.closest(".usa-modal-wrapper.is-visible")
  if (!targetModal) return null // modal isn't open; nothing to do yet

  if (!isListening) {
    document.body.addEventListener("keydown", handleKeydown, { capture: true })
    isListening = true
  }

  // Move focus back to the modal container itself
  targetModal.querySelector(".usa-modal")?.focus()

  return targetModal
}

// Call this once the modal has closed (see help.js's handleModalVisibilityChange)
// to remove the keydown guard.
export function detachHelpModalFocusTrap() {
  if (isListening) {
    document.body.removeEventListener("keydown", handleKeydown, { capture: true })
    isListening = false
  }
}
