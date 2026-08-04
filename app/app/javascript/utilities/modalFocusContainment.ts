import { trackUserAction } from "./api.js"

// How long, and how often, to keep checking whether focus has fallen back
// to document.body after we set it elsewhere.
const FOCUS_GUARD_WINDOW_MS = 2000
const FOCUS_GUARD_POLL_MS = 100

export function describeElement(el?: Element | null): string {
  if (!el) return "none"
  const id = el.id ? `#${el.id}` : ""
  const text = (el.textContent || "").trim().slice(0, 40)
  return `<${el.tagName.toLowerCase()}${id}> isConnected=${el.isConnected}${text ? ` text="${text}"` : ""}`
}

// Diagnostic only, for the "focus lands on <body> and stays there" reports
// seen on the demo deploy but not reproducible locally - reports which of
// triggerElement/fallback were missing/detached at the moment we gave up on
// them, so it can be removed again once root-caused.
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

// Polls document.activeElement instead of listening for a focus event:
// focus falling back to <body> (nothing else taking it) doesn't reliably
// dispatch a listenable focusout/focusin event, so reading the state
// directly is the only dependable signal. Only corrects when activeElement
// is exactly <body> - once it becomes any other real element, that's a
// legitimate focus change (e.g. the user tabbing away) and checking stops
// for good.
function guardFocus(target: HTMLElement): void {
  console.log("[modalFocusContainment] guardFocus watching:", describeElement(target))
  const deadline = Date.now() + FOCUS_GUARD_WINDOW_MS
  const check = () => {
    if (Date.now() >= deadline) {
      console.log("[modalFocusContainment] guardFocus window elapsed for:", describeElement(target))
      return
    }
    if (!document.body.contains(target)) {
      console.log(
        "[modalFocusContainment] guardFocus target left the DOM, stopping:",
        describeElement(target)
      )
      return
    }
    if (document.activeElement === target) {
      setTimeout(check, FOCUS_GUARD_POLL_MS)
      return
    }
    if (document.activeElement === document.body) {
      console.log(
        "[modalFocusContainment] guardFocus caught focus falling back to <body>, re-focusing:",
        describeElement(target)
      )
      target.focus()
      setTimeout(check, FOCUS_GUARD_POLL_MS)
      return
    }
    // Anything else: focus moved to a different real element - leave it alone.
    console.log(
      "[modalFocusContainment] guardFocus sees focus on a different element, giving up:",
      describeElement(document.activeElement)
    )
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

  console.log("[modalFocusContainment] restoreFocusTo called with:", {
    triggerElement: describeElement(triggerElement),
    fallback: describeElement(fallback),
    activeElementAtEntry: describeElement(activeElementAtEntry),
  })

  if (triggerElement && document.body.contains(triggerElement)) {
    console.log("[modalFocusContainment] focusing triggerElement:", describeElement(triggerElement))
    triggerElement.focus()
    guardFocus(triggerElement)
    return
  }
  console.log("[modalFocusContainment] triggerElement unavailable:", {
    truthy: !!triggerElement,
    inBody: triggerElement ? document.body.contains(triggerElement) : null,
  })

  if (fallback && document.body.contains(fallback)) {
    console.log("[modalFocusContainment] focusing fallback:", describeElement(fallback))
    fallback.focus()
    guardFocus(fallback)
    return
  }
  console.log("[modalFocusContainment] fallback unavailable:", {
    truthy: !!fallback,
    inBody: fallback ? document.body.contains(fallback) : null,
  })

  reportLostFocusTarget(triggerElement, fallback, activeElementAtEntry)

  document.body.setAttribute("tabindex", "-1")
  document.body.focus()
  document.body.removeAttribute("tabindex")
}
