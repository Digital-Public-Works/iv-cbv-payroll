import { Controller } from "@hotwired/stimulus"
import { trackUserAction } from "../utilities/api"
import { activateWithSpace } from "../utilities/accessibility"
import {
  rebuildHelpModalFocusTrap,
  detachHelpModalFocusTrap,
} from "../utilities/helpModalFocusTrap"

export default class extends Controller {
  static targets = ["content"]

  activateWithSpace = activateWithSpace

  handleClick(event) {
    if (event.target.href?.includes("#help-modal")) {
      trackUserAction("ApplicantOpenedHelpModal", {
        source: event.target.dataset.source,
      })
    }
  }

  // The modal's content is swapped via Turbo Frame navigation (topic links,
  // Go Back) rather than closing/reopening the modal, which leaves USWDS's
  // focus trap pointing at stale, detached elements. Rebuild it after every
  // frame swap so Tab/Shift+Tab keep working. See helpModalFocusTrap.js.
  handleFrameLoad = () => {
    rebuildHelpModalFocusTrap(this.contentTarget)
  }

  // usa-modal never destroys the modal's content when it closes - it just
  // hides it with CSS classes on the wrapper it builds around the modal - so
  // the Turbo Frame inside keeps showing whatever topic was last viewed.
  //
  // All three ways of closing the modal (close button, overlay click,
  // Escape) end up toggling "is-visible" off the same wrapper element, so
  // watching for that class change catches all of them without needing to
  // hook each one individually.
  handleModalVisibilityChange = (mutations) => {
    const wrapper = this.element.closest(".usa-modal-wrapper")
    if (!wrapper) return

    const modalJustClosed =
      mutations.some((mutation) => mutation.target === wrapper) &&
      !wrapper.classList.contains("is-visible")
    if (modalJustClosed) {
      detachHelpModalFocusTrap()
      document.querySelector("#help_modal_content").src = this.element.dataset.helpUrl
    }
  }

  connect() {
    document.addEventListener("click", this.handleClick)
    this.contentTarget.addEventListener("turbo:frame-load", this.handleFrameLoad)
    this.modalVisibilityObserver = new MutationObserver(this.handleModalVisibilityChange)
    this.modalVisibilityObserver.observe(document.body, {
      subtree: true,
      attributes: true,
      attributeFilter: ["class"],
    })
  }

  disconnect() {
    document.removeEventListener("click", this.handleClick)
    this.contentTarget.removeEventListener("turbo:frame-load", this.handleFrameLoad)
    this.modalVisibilityObserver.disconnect()
  }
}
