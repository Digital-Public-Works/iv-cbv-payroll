import { Controller } from "@hotwired/stimulus"
import { createModalAdapter } from "@js/utilities/createModalAdapter"
import { loadProviderResources } from "@js/utilities/loadProviderResources.ts"

export default class extends Controller {
  static targets = ["form", "userAccountId", "employerButton", "helpAlert"]

  static values = {
    cbvFlowId: Number,
  }

  async initialize() {
    await loadProviderResources()
  }

  async connect() {
    this.errorHandler = this.element.addEventListener("turbo:frame-missing", this.onTurboError)
    this.element.addEventListener("turbo:submit-start", this.onSearchStart)
  }

  disconnect() {
    this.element.removeEventListener("turbo:frame-missing", this.errorHandler)
    this.element.removeEventListener("turbo:submit-start", this.onSearchStart)
  }

  onTurboError(event) {
    console.warn("Got turbo error, redirecting:", event)

    const location = event.detail.response.url
    event.detail.visit(location)
    event.preventDefault()
  }

  onSearchStart(event) {
    const submitter = event.detail.formSubmission?.submitter

    if (submitter) submitter.disabled = false
  }

  onSuccess(accountId) {
    this.userAccountIdTarget.value = accountId
    this.formTarget.submit()
  }

  async select(event) {
    this.disableButtons()
    const { responseType, id, name, isDefaultOption, providerName } = event.currentTarget.dataset

    const adapter = createModalAdapter(providerName)

    if (!adapter) {
      console.error(`Could not find adapter for provider: ${providerName}`)
      return
    }

    adapter.init({
      requestData: {
        responseType,
        id,
        isDefaultOption,
        providerName,
        name,
      },
      onSuccess: this.onSuccess.bind(this),
      onExit: this.onExit.bind(this),
    })
    await adapter.open()
  }

  disableButtons() {
    this.employerButtonTargets.forEach((el) => el.setAttribute("disabled", "disabled"))
  }

  onExit() {
    this.showHelpBanner()
    this.employerButtonTargets.forEach((el) => el.removeAttribute("disabled"))
  }

  showHelpBanner() {
    this.helpAlertTargets.forEach((el) => el.classList.remove("display-none"))
  }
}
