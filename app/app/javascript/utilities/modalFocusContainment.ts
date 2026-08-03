// How long, and how often, to keep checking whether focus has fallen back
// to document.body after we set it elsewhere.
const FOCUS_GUARD_WINDOW_MS = 2000
const FOCUS_GUARD_POLL_MS = 100

// Polls document.activeElement instead of listening for a focus event:
// focus falling back to <body> (nothing else taking it) doesn't reliably
// dispatch a listenable focusout/focusin event, so reading the state
// directly is the only dependable signal. Only corrects when activeElement
// is exactly <body> - once it becomes any other real element, that's a
// legitimate focus change (e.g. the user tabbing away) and checking stops
// for good.
function guardFocus(target: HTMLElement): void {
  const deadline = Date.now() + FOCUS_GUARD_WINDOW_MS
  const check = () => {
    if (Date.now() >= deadline || !document.body.contains(target)) return
    if (document.activeElement === target) {
      setTimeout(check, FOCUS_GUARD_POLL_MS)
      return
    }
    if (document.activeElement === document.body) {
      target.focus()
      setTimeout(check, FOCUS_GUARD_POLL_MS)
    }
    // Anything else: focus moved to a different real element - leave it alone.
  }
  setTimeout(check, FOCUS_GUARD_POLL_MS)
}

/**
 * Restores focus to `triggerElement` if it's still in the DOM, else
 * `fallback`, else <body> as an absolute last resort. Focuses immediately,
 * then `guardFocus` keeps watch briefly in case a third-party widget's own
 * teardown resets focus back to <body> afterward.
 */
export function restoreFocusTo(triggerElement?: HTMLElement, fallback?: HTMLElement): void {
  if (triggerElement && document.body.contains(triggerElement)) {
    triggerElement.focus()
    guardFocus(triggerElement)
    return
  }
  if (fallback && document.body.contains(fallback)) {
    fallback.focus()
    guardFocus(fallback)
    return
  }
  document.body.setAttribute("tabindex", "-1")
  document.body.focus()
  document.body.removeAttribute("tabindex")
}
