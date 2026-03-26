import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "content"]

  connect() {
    this.dispatch("connected")
  }

  disconnect() {}

  expandContent() {
    this.contentTarget.hidden = false
    this.contentTarget.classList.remove("hidden")
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.dispatch("opened")
  }

  collapseContent() {
    this.contentTarget.hidden = true
    this.contentTarget.classList.add("hidden")
    this.triggerTarget.setAttribute("aria-expanded", "false")
    this.dispatch("closed")
  }

  setContentExpansion(event) {
    event.preventDefault()
    event.stopImmediatePropagation()
    const isExpanded = this.triggerTarget.getAttribute("aria-expanded") === "true"

    if (isExpanded) {
      this.collapseContent()
    } else {
      this.expandContent()
    }
  }
}
