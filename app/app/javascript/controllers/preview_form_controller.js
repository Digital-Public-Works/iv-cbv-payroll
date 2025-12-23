import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    console.log("PreviewFormController connected")
  }

  submit() {
    console.log("PreviewFormController submit called")
    this.element.requestSubmit()
  }

  navigateToRoute(event) {
    const selectedPath = event.target.value
    const currentParams = new URLSearchParams(window.location.search)
    const newUrl = selectedPath + (currentParams.toString() ? "?" + currentParams.toString() : "")
    window.location.href = newUrl
  }
}
