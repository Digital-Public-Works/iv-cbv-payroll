import { Controller } from "@hotwired/stimulus"

// Drives the create-invitation form: shows the fields belonging to the
// selected communication channel, swaps the submit button copy per channel,
// and keeps the submit button disabled until every visible required field is
// complete. Server-side validation remains the source of truth.
export default class extends Controller {
  static targets = ["channelFields", "submit"]

  connect() {
    this.update()
  }

  update() {
    const channel = this.selectedChannel()

    this.channelFieldsTargets.forEach((el) => {
      el.hidden = !channel || el.dataset.channel !== channel
    })

    if (this.hasSubmitTarget) {
      const labelKey = { link: "labelLink", sms: "labelSms", email: "labelEmail" }[channel]
      if (labelKey && this.submitTarget.dataset[labelKey]) {
        this.submitTarget.value = this.submitTarget.dataset[labelKey]
      }
      this.submitTarget.disabled = !this.requiredFieldsComplete()
    }
  }

  selectedChannel() {
    const checked = this.element.querySelector("input[name$='[communication_channel]']:checked")
    return checked ? checked.value : null
  }

  requiredFieldsComplete() {
    return this.requiredFields().every((field) => {
      if (field.type === "checkbox") return field.checked
      return field.value.trim() !== ""
    })
  }

  requiredFields() {
    const candidates = this.element.querySelectorAll(
      "input:not([type=hidden]):not([type=submit]):not([type=radio]), select, textarea"
    )

    return Array.from(candidates).filter((field) => this.isVisible(field) && this.isRequired(field))
  }

  isVisible(field) {
    return !field.closest("[hidden]")
  }

  isRequired(field) {
    if (field.dataset.required === "true") return true
    if (!field.id) return false

    const label = this.element.querySelector(`label[for="${CSS.escape(field.id)}"]`)
    return Boolean(label && label.querySelector(".usa-hint--required"))
  }
}
