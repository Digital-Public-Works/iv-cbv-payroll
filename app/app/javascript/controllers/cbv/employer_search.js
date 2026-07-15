import { Controller } from "@hotwired/stimulus"
import { createModalAdapter } from "@js/utilities/createModalAdapter"
import { loadProviderResources } from "@js/utilities/loadProviderResources.ts"

export default class extends Controller {
  static targets = [
    "form",
    "userAccountId",
    "employerButton",
    "helpAlert",
    "queryInput",
    "clearButton",
    "errorMessage",
    "searchForm",
  ]

  static values = {
    cbvFlowId: Number,
  }

  async initialize() {
    await loadProviderResources()
  }

  async connect() {
    this.element.addEventListener("turbo:frame-missing", this.onTurboError)
    this.element.addEventListener("turbo:submit-start", this.onSearchStart)
  }

  disconnect() {
    this.element.removeEventListener("turbo:frame-missing", this.onTurboError)
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

  toggleClearButton() {
    this.clearButtonTarget.hidden = this.queryInputTarget.value.length === 0
    if (this.queryInputTarget.value.length > 0) this.hideError()
  }

  onSearchReset(event) {
    event.preventDefault()
    this.queryInputTarget.value = ""
    this.clearButtonTarget.hidden = true
    this.queryInputTarget.focus()
  }

  onSubmit(event) {
    if (this.queryInputTarget.value.trim().length === 0) {
      event.preventDefault()
      this.showError()
    } else {
      this.hideError()
    }
  }

  toggleErrorIds(target, error) {
    let describeIds;

    if(error) {
      describeIds = "query_error_message" + " " + target.getAttribute("aria-describedby")
    } else {
      describeIds = target.getAttribute("aria-describedby").replace("query_error_message", "").trim()
    }

    this.queryInputTarget.setAttribute("aria-describedby", describeIds)
  }

  showError() {
    // const ariaLiveRegion = document.getElementById("live-announcer")
    // ariaLiveRegion.replaceChildren()
    // const pTag = document.createElement('p')
    document.getElementById("query_error_message").replaceChildren()
    document.getElementById("query_error_message").textContent = "HELLO WORLD"
    // pTag.textContent ="HELLO WORLD"
    // console.log("DROO", ariaLiveRegion)
    // console.log("DROO", pTag)

    // ariaLiveRegion.appendChild(pTag)
    this.errorMessageTarget.classList.remove("display-none")
    this.queryInputTarget.classList.add("usa-input--error")
    this.queryInputTarget.setAttribute("aria-invalid", "true")
    this.toggleErrorIds(this.queryInputTarget, true)
    this.searchFormTarget.classList.remove("margin-bottom-4")
  }

  hideError() {
    document.getElementById("query_error_message").replaceChildren()
    document.getElementById("query_error_message").textContent = "GOODBYE WORLD"
    // const ariaLiveRegion = document.getElementById("live-announcer")
    // ariaLiveRegion.replaceChildren()
    // const pTag = document.createElement('p')
    // pTag.textContent ="GOODBYE WORLD"
    // console.log("DROO", ariaLiveRegion)
    // console.log("DROO", pTag)

    // ariaLiveRegion.appendChild(pTag)
    this.errorMessageTarget.classList.add("display-none")
    this.queryInputTarget.classList.remove("usa-input--error")
    this.queryInputTarget.removeAttribute("aria-invalid")
    this.toggleErrorIds(this.queryInputTarget, false)
    this.searchFormTarget.classList.add("margin-bottom-4")
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
