import { Controller } from "@hotwired/stimulus"

const ERROR_CLASS = "usa-error-message"
const HINT_CLASS = "usa-hint"
// Matches USWDS's own debounce delay for its character count SR announcements.
const SR_ANNOUNCEMENT_DELAY = 1000

export default class extends Controller {
  static targets = ["input", "message", "srMessage", "submitButton"]
  static values = {
    maxlength: Number,
    overLimitText: String,
    shortenText: String,
  }

  connect() {
    // Announce the initial state right away (immediate: true) — there's no
    // typing to debounce yet, and USWDS's own implementation sets its
    // initial SR text synchronously too.
    this.render({ immediate: true })
  }

  disconnect() {
    clearTimeout(this.srTimeout)
  }

  guardSubmit(event) {
    if (this.submitButtonTarget.getAttribute("aria-disabled") === "true") {
      event.preventDefault()
    }
  }

  update() {
    // Every keystroke goes through here without `immediate`, so the SR
    // announcement gets debounced (see announceToScreenReader) instead of
    // firing on every character typed.
    this.render()
  }

  render({ immediate = false } = {}) {
    const length = this.inputTarget.value.length
    const over = length - this.maxlengthValue

    if (over > 0) {
      this.showError(over, immediate)
    } else {
      this.showCount(length, immediate)
    }
  }

  showCount(length, immediate) {
    const message = `${length}/${this.maxlengthValue}`
    this.messageTarget.textContent = message
    this.messageTarget.classList.remove(ERROR_CLASS)
    this.messageTarget.classList.add(HINT_CLASS)
    this.announceToScreenReader(message, immediate)

    this.inputTarget.classList.remove("usa-input--error")
    this.inputTarget.removeAttribute("aria-invalid")
    this.enableSubmit()
  }

  showError(over, immediate) {
    const message = `${this.overLimitTextValue.replace("{count}", over)} ${this.shortenTextValue}`

    this.messageTarget.textContent = message
    this.messageTarget.classList.remove(HINT_CLASS)
    this.messageTarget.classList.add(ERROR_CLASS)
    this.announceToScreenReader(message, immediate)

    this.inputTarget.classList.add("usa-input--error")
    this.inputTarget.setAttribute("aria-invalid", "true")
    this.disableSubmit()
  }

  announceToScreenReader(message, immediate) {
    // The visual counter (messageTarget) always updates instantly above —
    // this only controls the separate aria-live region. Screen readers
    // announce aria-live changes as soon as they land, so writing on every
    // keystroke would read the count aloud character by character. Instead
    // we clear any pending write and schedule a new one, so only the value
    // from the last keystroke before a pause actually reaches the live
    // region — a trailing-edge debounce, same delay USWDS itself uses.
    clearTimeout(this.srTimeout)

    if (immediate) {
      this.srMessageTarget.textContent = message
    } else {
      this.srTimeout = setTimeout(() => {
        this.srMessageTarget.textContent = message
      }, SR_ANNOUNCEMENT_DELAY)
    }
  }

  enableSubmit() {
    this.submitButtonTarget.setAttribute("aria-disabled", "false")
  }

  disableSubmit() {
    this.submitButtonTarget.setAttribute("aria-disabled", "true")
  }
}
