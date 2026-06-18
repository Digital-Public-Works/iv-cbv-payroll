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

  it("adds turbo:frame-missing and turbo:submit-start listeners on connect()", () => {
    expect(stimulusElement.addEventListener).toBeCalledTimes(2)
    expect(stimulusElement.addEventListener).toHaveBeenCalledWith(
      "turbo:frame-missing",
      expect.any(Function)
    )

    expect(stimulusElement.addEventListener).toHaveBeenCalledWith(
      "turbo:submit-start",
      expect.any(Function)
    )
  })

  it("removes turbo:frame-missing and turbo:submit-start listeners on disconnect()", async () => {
    await stimulusElement.remove()
    expect(stimulusElement.removeEventListener).toBeCalledTimes(2)
    const removedEvents = stimulusElement.removeEventListener.mock.calls.map((c) => c[0])
    expect(removedEvents).toContain("turbo:frame-missing")
    expect(removedEvents).toContain("turbo:submit-start")
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
