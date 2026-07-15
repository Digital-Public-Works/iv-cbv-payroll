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

  toggleErrorIds(target, error, id) {
    const describedbyList = target.getAttribute("aria-describedby")
    if (error && describedbyList.includes(id)) return
    let describeIds

    // TODO: DREW - should error id be first or second?
    if (error) {
      describeIds = id + " " + describedbyList
    } else {
      describeIds = describedbyList.replace(id, "").trim()
    }

    target.setAttribute("aria-describedby", describeIds)
  }

  updateAriaLiveRegion(text) {
    document.getElementById("live-announcer").replaceChildren()
    if (text) {
      document.getElementById("live-announcer").textContent = text
    }
  }

  showError() {
    // announce to the user the error message
    this.updateAriaLiveRegion(this.errorMessageTarget.textContent)
    // visually show the error message
    this.errorMessageTarget.classList.remove("display-none")
    // visually and programatically change the input to be in an error state, associate message with input
    this.queryInputTarget.classList.add("usa-input--error")
    this.queryInputTarget.setAttribute("aria-invalid", "true")
    this.toggleErrorIds(this.queryInputTarget, true, "query_error_message")
    // prevent error message from making content jump
    this.searchFormTarget.classList.remove("margin-bottom-4")
  }

  hideError() {
    // clear error message from live region
    this.updateAriaLiveRegion()
    // visually hide error message
    this.errorMessageTarget.classList.add("display-none")
    // visually and programatically remove input error state and associations
    this.queryInputTarget.classList.remove("usa-input--error")
    this.queryInputTarget.removeAttribute("aria-invalid")
    this.toggleErrorIds(this.queryInputTarget, false, "query_error_message")
    // revert styling
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
