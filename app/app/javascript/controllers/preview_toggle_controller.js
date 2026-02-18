import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["controls", "toggleButton"]

  connect() {
    const isCollapsed = localStorage.getItem("previewBarCollapsed") === "true"
    if (isCollapsed) {
      this.collapse()
    }
  }

  toggle() {
    const isCollapsed = this.element.classList.contains("preview-bar--collapsed")
    if (isCollapsed) {
      this.expand()
    } else {
      this.collapse()
    }
  }

  collapse() {
    this.element.classList.add("preview-bar--collapsed")
    this.toggleButtonTarget.textContent = "Show"
    localStorage.setItem("previewBarCollapsed", "true")
  }

  expand() {
    this.element.classList.remove("preview-bar--collapsed")
    this.toggleButtonTarget.textContent = "Hide"
    localStorage.setItem("previewBarCollapsed", "false")
  }
}
