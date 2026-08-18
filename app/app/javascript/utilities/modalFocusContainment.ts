import { trackUserAction } from "./api.js"

// How long, and how often, to keep checking whether focus has fallen back
// to document.body after we set it elsewhere.
const FOCUS_GUARD_WINDOW_MS = 2000
const FOCUS_GUARD_POLL_MS = 100

function describeElement(el?: Element | null): string {
  if (!el) return "none"
  const id = el.id ? `#${el.id}` : ""
  const text = (el.textContent || "").trim().slice(0, 40)
  return `<${el.tagName.toLowerCase()}${id}> isConnected=${el.isConnected}${text ? ` text="${text}"` : ""}`
}

// Low-noise safety net for the rare case both triggerElement and fallback
// are lost - cheap to keep as an early signal if it ever starts firing.
function reportLostFocusTarget(
  triggerElement: HTMLElement | undefined,
  fallback: HTMLElement | undefined,
  activeElementAtEntry: Element | null
): void {
  const details = {
    triggerElement: describeElement(triggerElement),
    fallback: describeElement(fallback),
    activeElementAtEntry: describeElement(activeElementAtEntry),
  }

  console.warn(
    "[modalFocusContainment] Falling back to <body> - neither triggerElement nor fallback are attached:",
    details
  )
  trackUserAction("DiagnosticModalFocusFellBackToBody", details).catch(() => {})
}

// Polls document.activeElement instead of listening for a focus event: focus
// falling back to <body> doesn't reliably dispatch a listenable
// focusout/focusin event, so reading the state directly is the only
// dependable signal. Only corrects when activeElement is exactly <body>,
// since <body> is never a real Tab-navigation target - anything else could
// be a legitimate user focus change, so it's left alone. Keeps polling for
// the full window even after seeing some other element, rather than giving
// up: a third-party widget's own close teardown can transiently bounce
// focus through its own DOM before settling on <body> a poll or two later.
function guardFocus(target: HTMLElement): void {
  const deadline = Date.now() + FOCUS_GUARD_WINDOW_MS
  const check = () => {
    if (Date.now() >= deadline) return
    if (!document.body.contains(target)) return
    if (document.activeElement === target) {
      setTimeout(check, FOCUS_GUARD_POLL_MS)
      return
    }
    if (document.activeElement === document.body) {
      target.focus()
      setTimeout(check, FOCUS_GUARD_POLL_MS)
      return
    }
    setTimeout(check, FOCUS_GUARD_POLL_MS)
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
  const activeElementAtEntry = document.activeElement

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

  reportLostFocusTarget(triggerElement, fallback, activeElementAtEntry)

  document.body.setAttribute("tabindex", "-1")
  document.body.focus()
  document.body.removeAttribute("tabindex")
}
