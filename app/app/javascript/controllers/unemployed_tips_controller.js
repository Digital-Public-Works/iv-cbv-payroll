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

  get accordion() {
    if (!this.hasTipsAccordionTarget) return null
    return this.application.getControllerForElementAndIdentifier(
      this.tipsAccordionTarget,
      "accordion"
    )
  }
}
