import { vi, describe, beforeEach, it, expect } from "vitest"
import EmployerSearchController from "@js/controllers/cbv/employer_search"
import { fetchPinwheelToken, fetchArgyleToken, trackUserAction } from "@js/utilities/api"
import loadScript from "load-script"
import {
  mockPinwheel,
  mockPinwheelAuthToken,
  mockPinwheelModule,
} from "@test/fixtures/pinwheel.fixture"
import { mockArgyle, mockArgyleAuthToken, mockArgyleModule } from "@test/fixtures/argyle.fixture.js"

vi.stubGlobal("Argyle", mockArgyleModule)
vi.stubGlobal("Pinwheel", mockPinwheelModule)

describe("EmployerSearchController", () => {
  let stimulusElement

  beforeEach(() => {
    stimulusElement = document.createElement("button")
    stimulusElement.setAttribute("data-controller", "cbv-employer-search")
    document.body.appendChild(stimulusElement)

    vi.spyOn(stimulusElement, "addEventListener")
    vi.spyOn(stimulusElement, "removeEventListener")

    window.Stimulus.register("cbv-employer-search", EmployerSearchController)
  })

  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("adds turbo:frame-missing, turbo:submit-start, and two turbo:frame-load listeners on connect()", () => {
    // Two separate turbo:frame-load listeners are registered: onFrameLoad
    // (results-heading announcement) and onPopularFrameLoad (tab focus
    // restoration) — they watch different frames and must both survive.
    expect(stimulusElement.addEventListener).toBeCalledTimes(4)
    expect(stimulusElement.addEventListener).toHaveBeenCalledWith(
      "turbo:frame-missing",
      expect.any(Function)
    )

    expect(stimulusElement.addEventListener).toHaveBeenCalledWith(
      "turbo:submit-start",
      expect.any(Function)
    )

    const frameLoadListenerCount = stimulusElement.addEventListener.mock.calls.filter(
      ([eventName]) => eventName === "turbo:frame-load"
    ).length
    expect(frameLoadListenerCount).toBe(2)
  })

  it("removes all four listeners, including both turbo:frame-load ones, on disconnect()", async () => {
    await stimulusElement.remove()
    expect(stimulusElement.removeEventListener).toBeCalledTimes(4)
    const removedEvents = stimulusElement.removeEventListener.mock.calls.map((c) => c[0])
    expect(removedEvents).toContain("turbo:frame-missing")
    expect(removedEvents).toContain("turbo:submit-start")

    const frameLoadRemovalCount = removedEvents.filter(
      (eventName) => eventName === "turbo:frame-load"
    ).length
    expect(frameLoadRemovalCount).toBe(2)
  })
})

describe("EmployerSearchController with pinwheel", () => {
  let stimulusElement

  beforeEach(async () => {
    stimulusElement = document.createElement("button")
    stimulusElement.setAttribute("data-controller", "cbv-employer-search")
    stimulusElement.setAttribute("data-action", "cbv-employer-search#select")
    stimulusElement.setAttribute("data-response-type", "employer")
    stimulusElement.setAttribute("data-id", "uuid")
    stimulusElement.setAttribute("data-is-default-option", false)
    stimulusElement.setAttribute("data-name", "test-name")
    stimulusElement.setAttribute("data-provider-name", "pinwheel")
    document.body.appendChild(stimulusElement)

    vi.spyOn(stimulusElement, "addEventListener")
    vi.spyOn(stimulusElement, "removeEventListener")

    await window.Stimulus.register("cbv-employer-search", EmployerSearchController)
  })

  afterEach(() => {
    document.body.innerHTML = ""
  })

  it.skip("loads Pinwheel modal from external website on click", async () => {
    await stimulusElement.click()
    expect(loadScript).toBeCalledTimes(1)
  })

  it("calls trackUserAction with data attributes from employer_search html", async () => {
    await stimulusElement.click()
    expect(await trackUserAction).toBeCalledTimes(1)
    expect(trackUserAction.mock.calls[0]).toMatchSnapshot()
  })
  it("fetches Pinwheel token", async () => {
    await stimulusElement.click()
    await fetchPinwheelToken
    expect(await fetchPinwheelToken).toBeCalled()
    expect(await fetchPinwheelToken.mock.results[0].value).toStrictEqual(mockPinwheelAuthToken)
    expect(fetchPinwheelToken.mock.calls[0]).toMatchSnapshot()
  })
})

describe("EmployerSearchController with argyle", () => {
  let stimulusElement

  beforeEach(async () => {
    stimulusElement = document.createElement("button")
    stimulusElement.setAttribute("data-controller", "cbv-employer-search")
    stimulusElement.setAttribute("data-action", "cbv-employer-search#select")
    stimulusElement.setAttribute("data-response-type", "employer")
    stimulusElement.setAttribute("data-id", "uuid")
    stimulusElement.setAttribute("data-is-default-option", false)
    stimulusElement.setAttribute("data-name", "test-name")
    stimulusElement.setAttribute("data-provider-name", "argyle")
    document.body.appendChild(stimulusElement)

    vi.spyOn(stimulusElement, "addEventListener")
    vi.spyOn(stimulusElement, "removeEventListener")

    await window.Stimulus.register("cbv-employer-search", EmployerSearchController)
  })

  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("loads argyle modal from external website on click", async () => {
    await stimulusElement.click()
    expect(loadScript).toBeCalledTimes(1)
    expect(loadScript.mock.calls[0]).toMatchSnapshot()
  })

  it("calls trackUserAction with data attributes from employer_search html", async () => {
    await stimulusElement.click()
    expect(await trackUserAction).toBeCalledTimes(1)
    expect(trackUserAction.mock.calls[0]).toMatchSnapshot()
  })
  it("fetches argyle token", async () => {
    await stimulusElement.click()
    await fetchArgyleToken
    expect(await fetchArgyleToken).toBeCalled()
    expect(await fetchArgyleToken.mock.results[0].value).toStrictEqual(mockArgyleAuthToken)
    expect(fetchArgyleToken.mock.calls[0]).toMatchSnapshot()
  })
})

describe("EmployerSearchController onSearchStart", () => {
  let controllerElement
  let form
  let submitButton

  beforeEach(async () => {
    controllerElement = document.createElement("div")
    controllerElement.setAttribute("data-controller", "cbv-employer-search")

    form = document.createElement("form")

    submitButton = document.createElement("button")
    submitButton.setAttribute("type", "submit")

    form.appendChild(submitButton)
    controllerElement.appendChild(form)
    document.body.appendChild(controllerElement)

    await window.Stimulus.register("cbv-employer-search", EmployerSearchController)
  })

  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("re-enables the submitter before the Turbo snapshot is captured", () => {
    submitButton.disabled = true

    const event = new CustomEvent("turbo:submit-start", {
      bubbles: true,
      detail: { formSubmission: { submitter: submitButton } },
    })
    form.dispatchEvent(event)

    expect(submitButton.disabled).toBe(false)
  })
})

describe("EmployerSearchController clear button", () => {
  let controllerElement
  let form
  let queryInput
  let clearButton

  beforeEach(async () => {
    controllerElement = document.createElement("div")
    controllerElement.setAttribute("data-controller", "cbv-employer-search")

    form = document.createElement("form")
    form.setAttribute("data-action", "reset->cbv-employer-search#onSearchReset")

    queryInput = document.createElement("input")
    queryInput.setAttribute("type", "search")
    queryInput.setAttribute("data-cbv-employer-search-target", "queryInput")
    queryInput.setAttribute("data-action", "input->cbv-employer-search#toggleClearButton")

    clearButton = document.createElement("button")
    clearButton.setAttribute("type", "reset")
    clearButton.setAttribute("data-cbv-employer-search-target", "clearButton")
    clearButton.hidden = true

    form.appendChild(queryInput)
    form.appendChild(clearButton)
    controllerElement.appendChild(form)
    document.body.appendChild(controllerElement)

    await window.Stimulus.register("cbv-employer-search", EmployerSearchController)
  })

  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("shows the clear button once the query input has a value", () => {
    queryInput.value = "Walmart"
    queryInput.dispatchEvent(new Event("input", { bubbles: true }))

    expect(clearButton.hidden).toBe(false)
  })

  it("hides the clear button again once the query input is emptied", () => {
    queryInput.value = "Walmart"
    queryInput.dispatchEvent(new Event("input", { bubbles: true }))
    expect(clearButton.hidden).toBe(false)

    queryInput.value = ""
    queryInput.dispatchEvent(new Event("input", { bubbles: true }))

    expect(clearButton.hidden).toBe(true)
  })

  it("hides the clear button and refocuses the input when the form is reset", () => {
    queryInput.value = "Walmart"
    queryInput.dispatchEvent(new Event("input", { bubbles: true }))
    expect(clearButton.hidden).toBe(false)

    form.dispatchEvent(new Event("reset", { bubbles: true }))

    expect(clearButton.hidden).toBe(true)
    expect(document.activeElement).toBe(queryInput)
  })

  it("empties the input on reset even when it was pre-filled from a query param", () => {
    // Simulates the server rendering `value: @query`, which becomes the
    // input's defaultValue that a native form reset would otherwise restore.
    queryInput.setAttribute("value", "Walmart")
    queryInput.value = "Walmart"
    queryInput.dispatchEvent(new Event("input", { bubbles: true }))

    form.dispatchEvent(new Event("reset", { bubbles: true, cancelable: true }))

    expect(queryInput.value).toBe("")
  })
})

describe("EmployerSearchController blank query error", () => {
  let controllerElement
  let form
  let queryInput
  let errorMessage
  let liveAnnouncer

  beforeEach(async () => {
    controllerElement = document.createElement("div")
    controllerElement.setAttribute("data-controller", "cbv-employer-search")

    form = document.createElement("form")
    form.setAttribute("data-action", "submit->cbv-employer-search#onSubmit")
    form.setAttribute("data-cbv-employer-search-target", "searchForm")
    form.classList.add("margin-bottom-4")

    queryInput = document.createElement("input")
    queryInput.setAttribute("type", "search")
    queryInput.setAttribute("data-cbv-employer-search-target", "queryInput")
    queryInput.setAttribute("data-action", "input->cbv-employer-search#toggleClearButton")
    queryInput.setAttribute("aria-describedby", "company_examples")

    const clearButton = document.createElement("button")
    clearButton.setAttribute("type", "reset")
    clearButton.setAttribute("data-cbv-employer-search-target", "clearButton")
    clearButton.hidden = true

    errorMessage = document.createElement("p")
    errorMessage.setAttribute("data-cbv-employer-search-target", "errorMessage")
    errorMessage.classList.add("display-none")
    errorMessage.textContent = "Enter letters or numbers"

    form.appendChild(queryInput)
    form.appendChild(clearButton)
    form.appendChild(errorMessage)
    controllerElement.appendChild(form)
    document.body.appendChild(controllerElement)

    // Rendered by the app layout in production; the controller reaches for
    // it by id, so it must exist in the DOM independent of this controller.
    liveAnnouncer = document.createElement("div")
    liveAnnouncer.id = "live-announcer"
    document.body.appendChild(liveAnnouncer)

    await window.Stimulus.register("cbv-employer-search", EmployerSearchController)
  })

  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("shows the error, prevents submission, and announces it when the query is blank", () => {
    const event = new Event("submit", { bubbles: true, cancelable: true })
    form.dispatchEvent(event)

    expect(event.defaultPrevented).toBe(true)
    expect(errorMessage.classList.contains("display-none")).toBe(false)
    expect(queryInput.classList.contains("usa-input--error")).toBe(true)
    expect(queryInput.getAttribute("aria-invalid")).toBe("true")
    expect(queryInput.getAttribute("aria-describedby")).toBe("query_error_message company_examples")
    expect(form.classList.contains("margin-bottom-4")).toBe(false)
    expect(liveAnnouncer.textContent).toBe("Enter letters or numbers")
  })

  it("shows the error and prevents submission when the query is only whitespace", () => {
    queryInput.value = "   "

    const event = new Event("submit", { bubbles: true, cancelable: true })
    form.dispatchEvent(event)

    expect(event.defaultPrevented).toBe(true)
    expect(errorMessage.classList.contains("display-none")).toBe(false)
  })

  it("does not show an error and allows submission when the query is present", () => {
    queryInput.value = "Walmart"

    const event = new Event("submit", { bubbles: true, cancelable: true })
    form.dispatchEvent(event)

    expect(event.defaultPrevented).toBe(false)
    expect(errorMessage.classList.contains("display-none")).toBe(true)
    expect(queryInput.classList.contains("usa-input--error")).toBe(false)
    expect(queryInput.getAttribute("aria-invalid")).toBeNull()
    expect(queryInput.getAttribute("aria-describedby")).toBe("company_examples")
  })

  it("hides the error, clears the announcement, and restores spacing as soon as the user types a character", () => {
    form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
    expect(errorMessage.classList.contains("display-none")).toBe(false)

    queryInput.value = "W"
    queryInput.dispatchEvent(new Event("input", { bubbles: true }))

    expect(errorMessage.classList.contains("display-none")).toBe(true)
    expect(queryInput.classList.contains("usa-input--error")).toBe(false)
    expect(queryInput.getAttribute("aria-invalid")).toBeNull()
    expect(queryInput.getAttribute("aria-describedby")).toBe("company_examples")
    expect(form.classList.contains("margin-bottom-4")).toBe(true)
    expect(liveAnnouncer.textContent).toBe("")
  })

  it("does not duplicate the error id in aria-describedby when submitted blank twice in a row", () => {
    form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
    form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))

    expect(queryInput.getAttribute("aria-describedby")).toBe("query_error_message company_examples")
  })
})

describe("EmployerSearchController results accessible announcement", () => {
  let controllerElement
  let employersFrame
  let resultsHeading
  let liveAnnouncer

  beforeEach(async () => {
    controllerElement = document.createElement("div")
    controllerElement.setAttribute("data-controller", "cbv-employer-search")

    employersFrame = document.createElement("turbo-frame")
    employersFrame.id = "employers"

    resultsHeading = document.createElement("h2")
    resultsHeading.setAttribute("data-cbv-employer-search-target", "resultsHeading")
    resultsHeading.textContent = "\n      Results (3)\n    "

    employersFrame.appendChild(resultsHeading)
    controllerElement.appendChild(employersFrame)
    document.body.appendChild(controllerElement)

    // Rendered by the app layout in production; the controller reaches for
    // it by id, so it must exist in the DOM independent of this controller.
    liveAnnouncer = document.createElement("div")
    liveAnnouncer.id = "live-announcer"
    document.body.appendChild(liveAnnouncer)

    await window.Stimulus.register("cbv-employer-search", EmployerSearchController)
  })

  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("announces the results heading text when the employers frame loads", () => {
    const event = new CustomEvent("turbo:frame-load", { bubbles: true })
    employersFrame.dispatchEvent(event)

    expect(liveAnnouncer.textContent).toBe("Results (3)")
  })

  it("announces again with the same text on a repeat search with an identical count", () => {
    employersFrame.dispatchEvent(new CustomEvent("turbo:frame-load", { bubbles: true }))
    liveAnnouncer.textContent = "stale content to prove it gets cleared"

    employersFrame.dispatchEvent(new CustomEvent("turbo:frame-load", { bubbles: true }))

    expect(liveAnnouncer.textContent).toBe("Results (3)")
  })

  it("ignores turbo:frame-load events from other frames on the page", () => {
    const popularFrame = document.createElement("turbo-frame")
    popularFrame.id = "popular"
    controllerElement.appendChild(popularFrame)

    popularFrame.dispatchEvent(new CustomEvent("turbo:frame-load", { bubbles: true }))

    expect(liveAnnouncer.textContent).toBe("")
  })
})

describe("EmployerSearchController multiple instances on same page!", () => {
  let stimulusElement1
  let stimulusElement2

  beforeEach(async () => {
    mockPinwheel()
    mockArgyle()

    stimulusElement1 = document.createElement("button")
    stimulusElement1.setAttribute("data-controller", "cbv-employer-search")
    stimulusElement1.setAttribute("data-action", "cbv-employer-search#select")
    stimulusElement1.setAttribute("data-response-type", "employer")
    stimulusElement1.setAttribute("data-id", "test-uuid-1")
    stimulusElement1.setAttribute("data-is-default-option", false)
    stimulusElement1.setAttribute("data-name", "ACME corp")
    stimulusElement1.setAttribute("data-provider-name", "pinwheel")

    stimulusElement2 = document.createElement("button")
    stimulusElement2.setAttribute("data-controller", "cbv-employer-search")
    stimulusElement2.setAttribute("data-action", "cbv-employer-search#select")
    stimulusElement2.setAttribute("data-response-type", "employer")
    stimulusElement2.setAttribute("data-id", "test-uuid-2")
    stimulusElement2.setAttribute("data-is-default-option", false)
    stimulusElement2.setAttribute("data-name", "Beta LLC")
    stimulusElement2.setAttribute("data-provider-name", "argyle")

    document.body.appendChild(stimulusElement1)
    document.body.appendChild(stimulusElement2)

    vi.spyOn(stimulusElement1, "addEventListener")
    vi.spyOn(stimulusElement1, "removeEventListener")
    vi.spyOn(stimulusElement2, "addEventListener")
    vi.spyOn(stimulusElement2, "removeEventListener")

    await window.Stimulus.register("cbv-employer-search", EmployerSearchController)
  })

  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("calls trackUserAction each time element is clicked", async () => {
    await stimulusElement1.click()
    await stimulusElement1.click()
    await stimulusElement2.click()
    await stimulusElement1.click()
    await stimulusElement1.click()

    expect(await trackUserAction).toBeCalledTimes(5)
    expect(trackUserAction.mock.calls[0]).toMatchSnapshot()
  })
  it.skip("fetches Pinwheel token each time the button is clicked", async () => {
    await stimulusElement1.click()
    await stimulusElement2.click()
    await stimulusElement1.click()
    await stimulusElement1.click()

    expect(await fetchPinwheelToken).toBeCalledTimes(4)
    expect(await fetchPinwheelToken.mock.results[0].value).toStrictEqual(mockPinwheelAuthToken)
    expect(fetchPinwheelToken.mock.calls[0]).toMatchSnapshot()
  })
  it("removal of one button does not impact function of other button.", async () => {
    await stimulusElement1.remove()
    await stimulusElement1.click()

    expect(await trackUserAction).toBeCalledTimes(0)
    await stimulusElement2.click()

    expect(await trackUserAction).toBeCalledTimes(1)
  })
})

describe("EmployerSearchController tab keyboard navigation", () => {
  let controllerElement
  let payrollTab
  let employerTab

  beforeEach(async () => {
    controllerElement = document.createElement("div")
    controllerElement.setAttribute("data-controller", "cbv-employer-search")

    payrollTab = document.createElement("a")
    payrollTab.setAttribute("data-cbv-employer-search-target", "tab")
    payrollTab.setAttribute("data-action", "keydown->cbv-employer-search#onTabKeydown")
    payrollTab.setAttribute("tabindex", "0")

    employerTab = document.createElement("a")
    employerTab.setAttribute("data-cbv-employer-search-target", "tab")
    employerTab.setAttribute("data-action", "keydown->cbv-employer-search#onTabKeydown")
    employerTab.setAttribute("tabindex", "-1")

    controllerElement.appendChild(payrollTab)
    controllerElement.appendChild(employerTab)
    document.body.appendChild(controllerElement)

    await window.Stimulus.register("cbv-employer-search", EmployerSearchController)

    payrollTab.focus()
  })

  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("moves focus and roving tabindex to the next tab on ArrowRight", () => {
    payrollTab.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true }))

    expect(document.activeElement).toBe(employerTab)
    expect(employerTab.getAttribute("tabindex")).toBe("0")
    expect(payrollTab.getAttribute("tabindex")).toBe("-1")
  })

  it("wraps focus around to the last tab on ArrowLeft from the first tab", () => {
    payrollTab.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowLeft", bubbles: true }))

    expect(document.activeElement).toBe(employerTab)
    expect(employerTab.getAttribute("tabindex")).toBe("0")
    expect(payrollTab.getAttribute("tabindex")).toBe("-1")
  })

  it("wraps focus around to the first tab on ArrowRight from the last tab", () => {
    employerTab.focus()
    employerTab.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true }))

    expect(document.activeElement).toBe(payrollTab)
    expect(payrollTab.getAttribute("tabindex")).toBe("0")
    expect(employerTab.getAttribute("tabindex")).toBe("-1")
  })

  it("moves focus to the last tab on End", () => {
    payrollTab.dispatchEvent(new KeyboardEvent("keydown", { key: "End", bubbles: true }))

    expect(document.activeElement).toBe(employerTab)
  })

  it("moves focus to the first tab on Home", () => {
    employerTab.focus()
    employerTab.dispatchEvent(new KeyboardEvent("keydown", { key: "Home", bubbles: true }))

    expect(document.activeElement).toBe(payrollTab)
  })

  it("activates the focused tab on Space without moving focus elsewhere", () => {
    employerTab.focus()
    vi.spyOn(employerTab, "click")

    employerTab.dispatchEvent(
      new KeyboardEvent("keydown", { key: " ", bubbles: true, cancelable: true })
    )

    expect(employerTab.click).toBeCalledTimes(1)
  })

  it("does not move focus or activate a tab on unrelated keys", () => {
    vi.spyOn(payrollTab, "click")

    payrollTab.dispatchEvent(new KeyboardEvent("keydown", { key: "a", bubbles: true }))

    expect(document.activeElement).toBe(payrollTab)
    expect(payrollTab.click).not.toBeCalled()
    expect(payrollTab.getAttribute("tabindex")).toBe("0")
  })
})

describe("EmployerSearchController tab focus restoration after frame reload", () => {
  let controllerElement
  let popularFrame
  let employerTab

  beforeEach(async () => {
    controllerElement = document.createElement("div")
    controllerElement.setAttribute("data-controller", "cbv-employer-search")

    popularFrame = document.createElement("div")
    popularFrame.id = "popular"

    employerTab = document.createElement("a")
    employerTab.id = "app_based_providers_tab"
    employerTab.setAttribute("href", "/cbv/employer_search?type=employer")
    employerTab.setAttribute("data-cbv-employer-search-target", "tab")
    employerTab.setAttribute(
      "data-action",
      "click->cbv-employer-search#onTabClick keydown->cbv-employer-search#onTabKeydown"
    )

    popularFrame.appendChild(employerTab)
    controllerElement.appendChild(popularFrame)
    document.body.appendChild(controllerElement)

    await window.Stimulus.register("cbv-employer-search", EmployerSearchController)
  })

  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("refocuses the activated tab's element (by id) once the popular frame finishes reloading", () => {
    employerTab.click()

    // Simulates Turbo tearing down and rebuilding the frame's contents on
    // navigation: the original tab node is gone, replaced by a new one that
    // happens to share the same id.
    const reloadedTab = document.createElement("a")
    reloadedTab.id = "app_based_providers_tab"
    reloadedTab.setAttribute("href", "/cbv/employer_search?type=employer")
    employerTab.replaceWith(reloadedTab)

    popularFrame.dispatchEvent(new CustomEvent("turbo:frame-load", { bubbles: true }))

    expect(document.activeElement).toBe(reloadedTab)
  })

  it("does nothing if the reloaded frame is not the popular frame", () => {
    employerTab.click()
    vi.spyOn(employerTab, "focus")

    const otherFrame = document.createElement("div")
    otherFrame.id = "employers"
    controllerElement.appendChild(otherFrame)

    otherFrame.dispatchEvent(new CustomEvent("turbo:frame-load", { bubbles: true }))

    expect(employerTab.focus).not.toBeCalled()
  })

  it("does nothing if no tab was clicked before the frame reloads", () => {
    expect(() =>
      popularFrame.dispatchEvent(new CustomEvent("turbo:frame-load", { bubbles: true }))
    ).not.toThrow()
  })

  it("still restores tab focus after the employers results frame has already loaded once", () => {
    // Regression test: onFrameLoad (results-heading announcement, in the
    // "employers" frame) used to tear down onPopularFrameLoad's listener as
    // a side effect, permanently breaking tab focus restoration for the
    // rest of the page's lifetime after any company-name search.
    const employersFrame = document.createElement("div")
    employersFrame.id = "employers"
    controllerElement.appendChild(employersFrame)
    employersFrame.dispatchEvent(new CustomEvent("turbo:frame-load", { bubbles: true }))

    employerTab.click()

    const reloadedTab = document.createElement("a")
    reloadedTab.id = "app_based_providers_tab"
    reloadedTab.setAttribute("href", "/cbv/employer_search?type=employer")
    employerTab.replaceWith(reloadedTab)

    popularFrame.dispatchEvent(new CustomEvent("turbo:frame-load", { bubbles: true }))

    expect(document.activeElement).toBe(reloadedTab)
  })
})
