import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "content"]

  setContentExpansion(event) {
    event.stopImmediatePropagation()
    const isExpanded = this.triggerTarget.getAttribute("aria-expanded") === "true"

    if (isExpanded) {
      this.collapseContent()
    } else {
      this.expandContent()
    }
  }
  expandContent() {
    this.contentTarget.hidden = false
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.triggerTarget.setAttribute("data-context-clicked-to-open", "true")
  }

  collapseContent() {
    this.contentTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
    this.triggerTarget.setAttribute("data-context-clicked-to-open", "false")
  }
}
