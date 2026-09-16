import FocusTrap from "@uswds/uswds/uswds-core/src/js/utils/focus-trap.js"
import components from "@uswds/uswds/src/js/components"

const modal = components.modal

// usa-modal builds its focus trap once, when the modal opens (toggleModal).
// Its firstTabStop/lastTabStop/focusableElements are captured in a closure
// at that moment and never recomputed. We swap the modal body via a Turbo
// Frame instead of closing/reopening the modal, so that closure goes stale.
// Call this after any Turbo Frame swap inside the modal to rebuild the trap
// against the live DOM, and to restore focus to the modal container.
//
// Returns the modal wrapper element if the modal was open (and the trap/focus
// were updated), or null if the modal wasn't open (nothing to do).
export function rebuildHelpModalFocusTrap(contentEl) {
  const targetModal = contentEl.closest(".usa-modal-wrapper.is-visible")
  if (!targetModal) return null // modal isn't open; the next real open builds its own trap

  if (modal.focusTrap) {
    modal.focusTrap.off() // detach the stale keydown listener; no other side effects
  }

  modal.focusTrap = FocusTrap(targetModal, {
    Escape: () => modal.toggleModal.call(modal, false), // mirrors usa-modal's onMenuClose
  })
  // Deliberately call add() instead of update(true)/on(): the latter also
  // runs FocusTrap's init(), which unconditionally focuses the trap's first
  // focusable element - e.g. stealing focus onto "Go Back" just because it's
  // first in the DOM. We handle focus placement ourselves (see below).
  modal.focusTrap.add(document.body)

  // Move focus back to the modal container itself - the same element
  // usa-modal's own toggleModal falls back to on open (it already carries
  // tabindex="-1" from USWDS's own setup). We deliberately avoid focusing
  // into the swapped content (e.g. the pane heading): parking focus on a
  // piece of content anchors a screen reader's virtual cursor there, which
  // gets in the way of reading through the new content normally.
  targetModal.querySelector(".usa-modal")?.focus()

  return targetModal
}
