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
 * Marks every other direct child of document.body `inert`, so background
 * content is unfocusable and hidden from the accessibility tree (including
 * screen reader virtual-cursor/arrow-key browsing) for as long as
 * `visibleElement` is the only thing meant to be interactive. Returns a
 * release function that restores exactly the elements this call inerted.
 */
export function containBackgroundFocus(visibleElement: HTMLElement): () => void {
  // document.body.children is already guaranteed to be Elements only, so no
  // instanceof check is needed here (unlike the MutationObserver callback
  // above, which sees arbitrary added nodes).
  const inertedSiblings = (Array.from(document.body.children) as HTMLElement[]).filter(
    (child) => child !== visibleElement && !child.inert
  )
  inertedSiblings.forEach((el) => {
    el.inert = true
  })

  return () => {
    inertedSiblings.forEach((el) => {
      el.inert = false
    })
  }
}
