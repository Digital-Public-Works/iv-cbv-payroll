import { Controller } from "@hotwired/stimulus"
import { trackUserAction } from "../utilities/api"

export default class extends Controller {
  static targets = ["copyLinkButton", "input", "successButton"]

  disconnect() {
    if (this.successTimer) clearTimeout(this.successTimer)
  }

  copy() {
    trackUserAction("ApplicantCopiedInvitationLink")
    if (!this.hasInputTarget) {
      return
    }

    navigator.clipboard.writeText(this.inputTarget.value).then(() => {
      this.showSuccess()
    })
  }

  showSuccess() {
    this.swap(this.copyLinkButtonTarget, this.successButtonTarget)

    // Clear any existing timeout before setting a new one
    if (this.successTimer) clearTimeout(this.successTimer)

    this.successTimer = setTimeout(() => {
      this.swap(this.successButtonTarget, this.copyLinkButtonTarget)
    }, 3000)
  }

  // Show `to` and hide `from`. A hidden element can't hold focus, so if `from`
  // is focused, move focus to `to` before hiding it; otherwise focus falls to <body>.
  swap(from, to) {
    const hadFocus = document.activeElement === from
    to.classList.remove("invisible")
    if (hadFocus) to.focus({ preventScroll: true })
    from.classList.add("invisible")
  }
}
