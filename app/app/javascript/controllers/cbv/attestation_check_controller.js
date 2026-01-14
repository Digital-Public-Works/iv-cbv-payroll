import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["attestationCheckbox", "submitButton"]

  connect() {
    this.setButton()
  }

  setButton() {
    const isChecked = this.attestationCheckboxTarget.checked

    if (isChecked) {
      this.enableSubmit()
    } else {
      this.disableSubmit()
    }
  }

  enableSubmit() {
    this.submitButtonTarget.setAttribute("aria-disabled", "false")
    this.submitButtonTarget.disabled = false
  }

  disableSubmit() {
    this.submitButtonTarget.setAttribute("aria-disabled", "true")
    this.submitButtonTarget.disabled = true
  }

  submit(event) {
    if (this.attestationCheckboxTarget.checked === false) {
      event.preventDefault()
      this.attestationCheckboxTarget.focus()
    }
  }
}
