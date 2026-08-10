/**
 * Calls back the first time an element matching `selector` is added as a
 * child of document.body (checking for one that already exists first).
 * Returns a cancel function - safe to call even after the callback has
 * already fired.
 */
export function onceElementAppears(
  selector: string,
  callback: (element: HTMLElement) => void
): () => void {
  const existing = document.querySelector<HTMLElement>(selector)
  if (existing) {
    callback(existing)
    return () => {}
  }

  const observer = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      for (const node of mutation.addedNodes) {
        // Not `instanceof HTMLElement`: test environments can run with
        // document/Node patched to a different realm than the ambient
        // HTMLElement global, which breaks cross-realm instanceof checks.
        // nodeType is a plain number, so it's realm-independent.
        if (node.nodeType !== Node.ELEMENT_NODE) continue
        const element = node as HTMLElement
        const match = element.matches(selector)
          ? element
          : element.querySelector<HTMLElement>(selector)
        if (match) {
          observer.disconnect()
          callback(match)
          return
        }
      }
    }
  })
  observer.observe(document.body, { childList: true })
  return () => observer.disconnect()
}

/**
 * Marks everything except `visibleElement` and its ancestors (up to
 * document.body) `inert`, so background content is unfocusable and hidden
 * from the accessibility tree (including screen reader virtual-cursor/arrow-
 * key browsing) for as long as `visibleElement` is the only thing meant to
 * be interactive. Walks the ancestor chain rather than just
 * document.body.children: visibleElement isn't guaranteed to be a direct
 * child of body itself (a third-party widget could nest its root deeper),
 * and inerting only at the top level would either take visibleElement down
 * with its own ancestor, or - if that ancestor turns out to hold other,
 * unrelated content too - fail to contain that other content at all.
 * Returns a release function that restores exactly the elements this call
 * inerted.
 */
export function containBackgroundFocus(visibleElement: HTMLElement): () => void {
  const inertedElements: HTMLElement[] = []
  let current: HTMLElement = visibleElement

  while (current !== document.body && current.parentElement) {
    // Iterates the live HTMLCollection by index rather than spreading it
    // into an array each level - this runs once per modal open, but it's
    // free to avoid the extra allocation.
    const siblings = current.parentElement.children
    for (let i = 0; i < siblings.length; i++) {
      const sibling = siblings[i] as HTMLElement
      if (sibling === current || sibling.inert) continue
      sibling.inert = true
      inertedElements.push(sibling)
    }
    current = current.parentElement
  }

  return () => {
    for (const el of inertedElements) {
      el.inert = false
    }
  }
}
