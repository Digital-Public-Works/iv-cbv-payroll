import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tipsAccordion", "closeLink"]
  static values = { open: Boolean }

  closeTipsExternal(event) {
    const isSearchRequest = event.target.classList.contains("usa-search")
    const isEmployerButtonClick =
      event.type === "click" &&
      event.target.closest('[data-cbv-employer-search-target="employerButton"]')

    if (isSearchRequest || isEmployerButtonClick) {
      this.closeTips()
    }
  }

  closeTips() {
    const accordion = this.application.getControllerForElementAndIdentifier(
      this.tipsAccordionTarget,
      "accordion"
    )
    if (accordion) {
      accordion.collapseContent()
    }
  }

  openTips() {
    const accordion = this.application.getControllerForElementAndIdentifier(
      this.tipsAccordionTarget,
      "accordion"
    )
    if (accordion) {
      accordion.expandContent()
    }
  }
  tipsAccordionTargetConnected(element) {
    element.addEventListener("accordion:opened", () => {
      this.openValue = true
      sessionStorage.setItem("unemployed_tips_open", this.openValue)
      console.log(this.openValue)
    })
    element.addEventListener("accordion:closed", () => {
      this.openValue = false
      sessionStorage.setItem("unemployed_tips_open", this.openValue)
      console.log(this.openValue)
    })
    element.addEventListener("accordion:connected", () => {
      this.checkTips()
    })
  }
  checkTips() {
    if (sessionStorage.getItem("unemployed_tips_open") === "true") {
      this.openTips()
    }
    this.closeTips()
  }
}
