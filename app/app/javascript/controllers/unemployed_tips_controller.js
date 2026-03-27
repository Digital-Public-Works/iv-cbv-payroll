import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tipsAccordion", "closeLink"]
  static values = { open: Boolean }

  closeTipsExternal(event) {
    const isSearchRequest =
      event.type === "turbo:before-fetch-request" && event.target.classList.contains("usa-search")
    const isEmployerButtonClick =
      event.type === "click" &&
      event.target.closest('[data-cbv-employer-search-target="employerButton"]')

    if (isSearchRequest || isEmployerButtonClick) {
      this.closeTips()
    }
  }

  closeTips() {
    this.accordion?.collapseContent()
  }

  openTips() {
    this.accordion?.expandContent()
  }
  tipsAccordionTargetConnected(element) {
    element.addEventListener("accordion:opened", () => {
      this.openValue = true
      sessionStorage.setItem("unemployed_tips_open", this.openValue)
    })
    element.addEventListener("accordion:closed", () => {
      this.openValue = false
      sessionStorage.setItem("unemployed_tips_open", this.openValue)
    })
    element.addEventListener("accordion:connected", () => {
      this.checkTips()
    })
  }
  checkTips() {
    if (sessionStorage.getItem("unemployed_tips_open") === "true") {
      this.openTips()
    }
  }

  get accordion() {
    if (!this.hasTipsAccordionTarget) return null
    return this.application.getControllerForElementAndIdentifier(
      this.tipsAccordionTarget,
      "accordion"
    )
  }
}
