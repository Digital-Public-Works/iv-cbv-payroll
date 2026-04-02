import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "content"]

  static values = {
    expanded: { type: Boolean, default: false },
    clickedToOpen: { type: Boolean, default: false },
  }

  expandedValueChanged(value) {
    if (!this.hasTriggerTarget || !this.hasContentTarget) return

    this.clickedToOpenValue = !this.clickedToOpenValue
    this.triggerTarget.setAttribute("data-context-clicked-to-open", this.clickedToOpenValue)
  }

  setContentExpansion(event) {
    this.expandedValue = !this.expandedValue
  }

  collapseContent() {
    this.contentTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
    this.expandedValue = false
  }
}
