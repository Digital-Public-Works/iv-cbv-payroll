import { Controller } from "@hotwired/stimulus"

// Shows the SMS-only form fields (phone number, attestation) when the SMS
// communication channel is selected.
export default class extends Controller {
  static targets = ["smsFields"]

  connect() {
    this.toggle()
  }

  toggle() {
    const selected = this.element.querySelector("input[name$='[communication_channel]']:checked")
    const isSms = Boolean(selected) && selected.value === "sms"

    this.smsFieldsTargets.forEach((el) => {
      el.hidden = !isSms
    })
  }
}
