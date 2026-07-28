import { Controller } from "@hotwired/stimulus"
import { createModalAdapter } from "@js/utilities/createModalAdapter"
import { loadProviderResources } from "@js/utilities/loadProviderResources.ts"
import { toggleErrorIds, updateAriaLiveRegion } from "@js/utilities/accessibility"

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
    "resultsHeading",
    "tab",
  ]

  static values = {
    cbvFlowId: Number,
  }

  // Turbo replaces the popular-providers frame's contents on every tab
  // activation, which drops focus. Recorded here (by id, since the tab
  // elements themselves get destroyed and recreated) so it can be restored
  // once the frame finishes reloading — see onTabClick/onPopularFrameLoad.
  pendingTabFocusId = null

  onPopularFrameLoad = (event) => {
    if (event.target.id !== "popular" || !this.pendingTabFocusId) return

    const tabToFocus = document.getElementById(this.pendingTabFocusId)
    this.pendingTabFocusId = null
    tabToFocus?.focus()
  }

  async initialize() {
    await loadProviderResources()
  }

  async connect() {
    this.onFrameLoad = this.onFrameLoad.bind(this)
    this.element.addEventListener("turbo:frame-missing", this.onTurboError)
    this.element.addEventListener("turbo:submit-start", this.onSearchStart)
    this.element.addEventListener("turbo:frame-load", this.onFrameLoad)
    this.element.addEventListener("turbo:frame-load", this.onPopularFrameLoad)
  }

  disconnect() {
    this.element.removeEventListener("turbo:frame-missing", this.onTurboError)
    this.element.removeEventListener("turbo:submit-start", this.onSearchStart)
    this.element.removeEventListener("turbo:frame-load", this.onFrameLoad)
  }

  onFrameLoad(event) {
    // Preventing the heading from being announced when the "Popular" tab is selected and the turbo frame is loaded.
    if (event.target.id !== "employers") return

    if (this.hasResultsHeadingTarget) {
      updateAriaLiveRegion(this.resultsHeadingTarget.textContent.trim())
    }
    this.element.removeEventListener("turbo:frame-load", this.onPopularFrameLoad)
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

  showError() {
    // announce to the user the error message
    updateAriaLiveRegion(this.errorMessageTarget.textContent)
    // visually show the error message
    this.errorMessageTarget.classList.remove("display-none")
    // visually and programatically change the input to be in an error state, associate message with input
    this.queryInputTarget.classList.add("usa-input--error")
    this.queryInputTarget.setAttribute("aria-invalid", "true")
    toggleErrorIds(this.queryInputTarget, true, "query_error_message")
    // prevent error message from making content jump
    this.searchFormTarget.classList.remove("margin-bottom-4")
  }

  hideError() {
    // clear error message from live region
    updateAriaLiveRegion()
    // visually hide error message
    this.errorMessageTarget.classList.add("display-none")
    // visually and programatically remove input error state and associations
    this.queryInputTarget.classList.remove("usa-input--error")
    this.queryInputTarget.removeAttribute("aria-invalid")
    toggleErrorIds(this.queryInputTarget, false, "query_error_message")
    // revert styling
    this.searchFormTarget.classList.add("margin-bottom-4")
  }

  onTabClick(event) {
    this.pendingTabFocusId = event.currentTarget.id
  }

  onTabKeydown(event) {
    const tabs = this.tabTargets
    // finds which tab just received the keydown from the element listener it is bound to,
    // i.e. whichever tab is currently focused.
    const currentIndex = tabs.indexOf(event.currentTarget)
    let newIndex

    switch (event.key) {
      case "ArrowLeft":
      case "ArrowUp":
        // Move to previous tab
        // wraps from tab 0 to the last tab
        // (+ tabs.length avoids a negative index before %)
        newIndex = (currentIndex - 1 + tabs.length) % tabs.length
        break
      case "ArrowRight":
      case "ArrowDown":
        // Move to next tab
        // wraps past the last tab to tab 0
        newIndex = (currentIndex + 1) % tabs.length
        break
      case "Home":
        newIndex = 0
        break
      case "End":
        newIndex = tabs.length - 1
        break
      case " ":
      case "Spacebar":
        // NOTE: case is neccessary because the event targets (tab controls) are links
        // links only activate on Enter keypress by default
        event.preventDefault()
        event.currentTarget.click()
        return
      default:
        // no action, allow the browser's default handling to apply
        return
    }

    event.preventDefault()
    tabs.forEach((tab) => tab.setAttribute("tabindex", "-1"))
    tabs[newIndex].setAttribute("tabindex", "0")
    tabs[newIndex].focus()
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
      triggerElement: event.currentTarget,
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
