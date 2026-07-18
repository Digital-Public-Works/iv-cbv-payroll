import { Controller } from "@hotwired/stimulus"

const ERROR_CLASS = "usa-error-message"
const HINT_CLASS = "usa-hint"

export default class extends Controller {
  static targets = ["input", "message", "srMessage", "submitButton"]
  static values = {
    maxlength: Number,
    overLimitText: String,
    shortenText: String,
  }

  connect() {
    this.update()
  }

  guardSubmit(event) {
    if (this.submitButtonTarget.getAttribute("aria-disabled") === "true") {
      event.preventDefault()
    }
  }

  update() {
    const length = this.inputTarget.value.length
    const over = length - this.maxlengthValue

    if (over > 0) {
      this.showError(over)
    } else {
      this.showCount(length)
    }
  }

  showCount(length) {
    this.messageTarget.textContent = `${length}/${this.maxlengthValue} characters remaining`
    this.messageTarget.classList.remove(ERROR_CLASS)
    this.messageTarget.classList.add(HINT_CLASS)
    this.srMessageTarget.textContent = ""

    this.inputTarget.classList.remove("usa-input--error")
    this.inputTarget.removeAttribute("aria-invalid")
    this.enableSubmit()
  }

  showError(over) {
    const message = `${this.overLimitTextValue.replace("{count}", over)} ${this.shortenTextValue}`

    this.messageTarget.textContent = message
    this.messageTarget.classList.remove(HINT_CLASS)
    this.messageTarget.classList.add(ERROR_CLASS)
    this.srMessageTarget.textContent = message

    this.inputTarget.classList.add("usa-input--error")
    this.inputTarget.setAttribute("aria-invalid", "true")
    this.disableSubmit()
  }

  enableSubmit() {
    this.submitButtonTarget.setAttribute("aria-disabled", "false")
  }

  disableSubmit() {
    this.submitButtonTarget.setAttribute("aria-disabled", "true")
  }
}
