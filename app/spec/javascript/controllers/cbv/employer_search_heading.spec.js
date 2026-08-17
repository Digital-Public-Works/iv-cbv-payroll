import { describe, beforeEach, afterEach, it, expect, vi } from "vitest"
import { Application } from "@hotwired/stimulus"

vi.mock("@js/utilities/loadProviderResources.ts", () => ({
  loadProviderResources: vi.fn().mockResolvedValue(undefined),
}))
vi.mock("@js/utilities/createModalAdapter", () => ({
  createModalAdapter: vi.fn(),
}))
vi.mock("@js/utilities/accessibility", () => ({
  toggleErrorIds: vi.fn(),
  updateAriaLiveRegion: vi.fn(),
}))

import EmployerSearchController from "@js/controllers/cbv/employer_search.js"

const DEFAULT = "Find your employer or payroll company"
const RESULTS = "Search results"

async function setup() {
  document.body.innerHTML = `
    <div data-controller="cbv-employer-search"
         data-cbv-employer-search-heading-default-value="${DEFAULT}"
         data-cbv-employer-search-heading-results-value="${RESULTS}">
      <h1 data-cbv-employer-search-target="pageHeading">${DEFAULT}</h1>
      <form data-action="reset->cbv-employer-search#onSearchReset">
        <input data-cbv-employer-search-target="queryInput" />
        <button type="reset" data-cbv-employer-search-target="clearButton"></button>
      </form>
      <turbo-frame id="employers"></turbo-frame>
    </div>
  `
  const application = Application.start()
  application.register("cbv-employer-search", EmployerSearchController)
  await new Promise((resolve) => setTimeout(resolve, 0))
  return application
}

const h1 = () => document.querySelector("[data-cbv-employer-search-target='pageHeading']")
const queryInput = () => document.querySelector("[data-cbv-employer-search-target='queryInput']")
const loadEmployersFrame = () =>
  document
    .getElementById("employers")
    .dispatchEvent(new CustomEvent("turbo:frame-load", { bubbles: true }))

describe("cbv/employer_search — page heading", () => {
  let application

  afterEach(() => {
    application?.stop()
    document.body.innerHTML = ""
    vi.clearAllMocks()
  })

  it("switches the heading to the results text when the frame loads with a query", async () => {
    application = await setup()
    queryInput().value = "walmart"

    loadEmployersFrame()

    expect(h1().textContent).toBe(RESULTS)
  })

  it("keeps the default prompt when the frame loads with no query", async () => {
    application = await setup()
    queryInput().value = ""

    loadEmployersFrame()

    expect(h1().textContent).toBe(DEFAULT)
  })

  it("does not flip the heading the moment the search box is cleared (results still shown)", async () => {
    application = await setup()
    queryInput().value = "walmart"
    loadEmployersFrame()
    expect(h1().textContent).toBe(RESULTS)

    document.querySelector("form").dispatchEvent(new Event("reset", { bubbles: true }))

    expect(h1().textContent).toBe(RESULTS)
  })
})
