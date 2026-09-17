import FocusTrap from "@uswds/uswds/uswds-core/src/js/utils/focus-trap.js"

// IMPORTANT: this file must not import USWDS's shared `modal` singleton
// (e.g. via "@uswds/uswds/src/js/components").

let activeTrap = null

// usa-modal builds its own focus trap once, when the modal opens, and never
// recomputes its firstTabStop/lastTabStop/focusableElements. We swap the
// modal body via a Turbo Frame instead of closing/reopening the modal, so
// that closure goes stale. Call this after any Turbo Frame swap inside the
// modal to rebuild a trap against the live DOM, and to restore focus to the
// modal container.
//
// This does NOT handle Escape-to-close: whichever trap usa-modal itself
// created when the modal was opened already does that correctly on its own.
//
// Returns the modal wrapper element if the modal was open (and the trap/focus
// were updated), or null if the modal wasn't open (nothing to do).
export function rebuildHelpModalFocusTrap(contentEl) {
  const targetModal = contentEl.closest(".usa-modal-wrapper.is-visible")
  if (!targetModal) return null // modal isn't open; the next real open builds its own trap

  if (activeTrap) {
    activeTrap.off() // detach the stale keydown listener; no other side effects
  }

  activeTrap = FocusTrap(targetModal)
  // Deliberately call add() instead of update(true)/on(): the latter also
  // runs FocusTrap's init(), which unconditionally focuses the trap's first
  // focusable element - e.g. stealing focus onto "Go Back" just because it's
  // first in the DOM. We handle focus placement ourselves (see below).
  activeTrap.add(document.body)

  // Move focus back to the modal container itself - the same element
  // usa-modal's own toggleModal falls back to on open (it already carries
  // tabindex="-1" from USWDS's own setup).
  targetModal.querySelector(".usa-modal")?.focus()

  return targetModal
}

// Call this once the modal has closed (see help.js's handleModalVisibilityChange)
// to detach this trap's own keydown listener. We rely on our own observation
// of the modal's visibility rather than any close/toggle callback, since a
// close path invoking a *different* module instance's toggleModal - USWDS's
// own trap lives in a separate instance from this file's - has no way to know
// about (or correctly clean up) this trap.
export function detachHelpModalFocusTrap() {
  if (activeTrap) {
    activeTrap.off()
    activeTrap = null
  }
}
