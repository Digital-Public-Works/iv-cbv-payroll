import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tipsAccordion", "closeLink"]

  connect() {
    Promise.resolve().then(() => {
      this.setUnemployedTipSource()
    })
  }

  closeTipsExternal(event) {
    const isSearchRequest =
      event.type === "turbo:before-fetch-request" && event.target.classList.contains("usa-search")
    const isPopularPayrollAppSwitch =
      event.type === "turbo:before-fetch-request" && event.target.id === "popular"
    const isEmployerButtonClick =
      event.type === "click" &&
      event.target.closest('[data-cbv-employer-search-target="employerButton"]')

    if (isSearchRequest || isPopularPayrollAppSwitch || isEmployerButtonClick) {
      this.closeTips()
    }
  }

  closeTips() {
    this.accordion?.collapseContent()
  }

  setUnemployedTipSource() {
    this.accordion?.triggerTarget.setAttribute("data-context-unemployed-links-source", "link")
  }

  get accordion() {
    if (!this.hasTipsAccordionTarget) return null
    return this.application.getControllerForElementAndIdentifier(
      this.tipsAccordionTarget,
      "accordion"
    )
  }
}
