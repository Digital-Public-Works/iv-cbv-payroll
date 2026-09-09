import { Controller } from "@hotwired/stimulus"

// Submits the form this controller is attached to when an input changes,
// e.g. the admin portal's agency selector.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
