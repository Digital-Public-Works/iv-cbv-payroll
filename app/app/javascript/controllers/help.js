import { Controller } from "@hotwired/stimulus"
import { trackUserAction } from "../utilities/api"
import { rebuildHelpModalFocusTrap } from "../utilities/helpModalFocusTrap"

export default class extends Controller {
  static targets = ["content"]

  handleClick(event) {
    if (event.target.href?.includes("#help-modal")) {
      trackUserAction("ApplicantOpenedHelpModal", {
        source: event.target.dataset.source,
      })
      // reset the help modal src on mousedown to ensure the help modal src is reset to "/help"
      document.querySelector("#help_modal_content").src = event.target.dataset.helpUrl
    }
  }

  // The modal's content is swapped via Turbo Frame navigation (topic links,
  // Go Back) rather than closing/reopening the modal, which leaves USWDS's
  // focus trap pointing at stale, detached elements. Rebuild it after every
  // frame swap so Tab/Shift+Tab keep working. See helpModalFocusTrap.js.
  handleFrameLoad = () => {
    rebuildHelpModalFocusTrap(this.contentTarget)
  }

  connect() {
    document.addEventListener("click", this.handleClick)
    this.contentTarget.addEventListener("turbo:frame-load", this.handleFrameLoad)
  }

  disconnect() {
    document.removeEventListener("click", this.handleClick)
    this.contentTarget.removeEventListener("turbo:frame-load", this.handleFrameLoad)
  }
}
