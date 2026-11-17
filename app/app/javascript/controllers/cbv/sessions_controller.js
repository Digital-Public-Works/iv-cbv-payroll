import { Controller } from "@hotwired/stimulus"
import { trackUserAction } from "../../utilities/api"
import {
  currentCbvFlowId,
  goToSwitchedPage,
  localizedPath,
  navigateTo,
  renderedFromHistory,
} from "../../utilities/cbvFlowBinding"

const ACTIVITY_KEY = "cbv-session-activity"

const parseActivity = (value) => {
  if (!value) return null
  try {
    const parsed = JSON.parse(value)
    return parsed && typeof parsed === "object" ? parsed : { flowId: null, at: parsed }
  } catch {
    return null
  }
}

export default class extends Controller {
  static targets = ["modal"]

  timeoutValue
  originalPinwheelZIndex

  connect() {
    this.timeoutValue = parseInt(this.modalTarget.dataset.itemTimeoutParam)
    this.setupTimers()
    if (!renderedFromHistory()) this.announceActivity()
    window.addEventListener("storage", this.handleStorage)
    window.addEventListener("pageshow", this.handlePageShow)
    document.addEventListener("turbo:submit-end", this.handleSubmitEnd)

    // Add event listeners for modal open/close
    document
      .getElementById("open-session-modal-button")
      .addEventListener("click", this.handleModalOpen.bind(this))
    const closeButtons = document.querySelectorAll("[data-close-modal]")
    closeButtons.forEach((button) => {
      button.addEventListener("click", this.handleModalClose.bind(this))
    })
  }

  setupTimers() {
    // Clear existing timers if they exist
    if (this.warningTimer) clearTimeout(this.warningTimer)
    if (this.expirationTimer) clearTimeout(this.expirationTimer)

    // Calculate when to show the warning (5 minutes before expiration)
    const warningDelay = Math.max(this.timeoutValue - 5 * 60, 0) * 1000
    const expirationDelay = this.timeoutValue * 1000

    // Set timer for the warning (5 minutes before expiration)
    this.warningTimer = setTimeout(() => {
      // Close all modals except the session timeout modal
      const closeButtons = document.querySelectorAll("[data-close-modal]")
      closeButtons.forEach((button) => {
        // Skip if this button is inside the session timeout modal
        if (!button.closest("#session-timeout-modal")) {
          button.click()
        }
      })
      document.getElementById("open-session-modal-button").click()
      // Track that the applicant was warned about timeout
      trackUserAction("ApplicantWarnedAboutTimeout")
    }, warningDelay)

    // Set timer for the actual session expiration
    this.expirationTimer = setTimeout(() => {
      navigateTo(localizedPath("/cbv/session/end?timeout=true"))
    }, expirationDelay)
  }

  handleModalOpen() {
    // Find the pinwheel portal if it exists
    const pinwheelPortal = document.querySelector(".pinwheel-portal")
    if (pinwheelPortal) {
      // Store the original z-index
      this.originalPinwheelZIndex =
        pinwheelPortal.style.zIndex || getComputedStyle(pinwheelPortal).zIndex
      pinwheelPortal.style.zIndex = "0"
    }
  }

  handleModalClose() {
    // Restore the original z-index when the session modal is closed
    const pinwheelPortal = document.querySelector(".pinwheel-portal")
    if (pinwheelPortal && this.originalPinwheelZIndex) {
      pinwheelPortal.style.zIndex = this.originalPinwheelZIndex
    }
  }

  /*
   reset the timers when the session is extended
   see _timeout_modal.html.erb for the button that triggers this
  */
  resetTimers() {
    this.setupTimers()
  }

  handlePageShow = (event) => {
    if (event.persisted) this.setupTimers()
  }

  handleSubmitEnd = (event) => {
    const submitter = event.detail?.formSubmission?.submitter
    if (submitter?.id === "extend-session-button" && event.detail.success) {
      this.announceActivity()
    }
  }

  // another tab is active
  handleStorage = (event) => {
    if (event.key !== ACTIVITY_KEY) return

    const activity = parseActivity(event.newValue)
    if (!activity) return

    // if own flow, keep. if different flow, redirect
    const ownFlowId = currentCbvFlowId()
    if (activity.flowId && ownFlowId && String(activity.flowId) !== ownFlowId) {
      this.clearTimers()
      goToSwitchedPage()
      return
    }

    this.setupTimers()
  }

  announceActivity() {
    const flowId = currentCbvFlowId()
    if (!flowId) return
    if (document.documentElement.hasAttribute("data-turbo-preview")) return

    try {
      window.localStorage.setItem(ACTIVITY_KEY, JSON.stringify({ flowId, at: Date.now() }))
    } catch {
      // Storage unavailable (e.g. blocked); the server-side checks still apply.
    }
  }

  clearTimers() {
    if (this.warningTimer) clearTimeout(this.warningTimer)
    if (this.expirationTimer) clearTimeout(this.expirationTimer)
  }

  trackExtend() {
    trackUserAction("ApplicantExtendedSession")
  }

  trackEnd() {
    trackUserAction("ApplicantEndedSession")
  }

  disconnect() {
    if (this.warningTimer) clearTimeout(this.warningTimer)
    if (this.expirationTimer) clearTimeout(this.expirationTimer)
    window.removeEventListener("storage", this.handleStorage)
    window.removeEventListener("pageshow", this.handlePageShow)
    document.removeEventListener("turbo:submit-end", this.handleSubmitEnd)

    // Remove event listeners
    document
      .getElementById("open-session-modal-button")
      ?.removeEventListener("click", this.handleModalOpen)
    const closeButtons = document.querySelectorAll("[data-close-modal]")
    closeButtons.forEach((button) => {
      button.removeEventListener("click", this.handleModalClose)
    })
  }
}
