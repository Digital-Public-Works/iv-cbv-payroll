import { Controller } from "@hotwired/stimulus"

// Copies the previewed JSON payload to the clipboard and briefly swaps the
// button label to confirm. Used by the preview "Transmitted JSON" page.
export default class extends Controller {
  static targets = ["source", "button"]

  disconnect() {
    if (this.resetTimer) clearTimeout(this.resetTimer)
  }

  copy() {
    if (!this.hasSourceTarget) return

    navigator.clipboard.writeText(this.sourceTarget.textContent).then(() => {
      if (!this.hasButtonTarget) return

      const original = this.buttonTarget.textContent
      this.buttonTarget.textContent = "Copied!"

      if (this.resetTimer) clearTimeout(this.resetTimer)
      this.resetTimer = setTimeout(() => {
        this.buttonTarget.textContent = original
      }, 2000)
    })
  }
}
