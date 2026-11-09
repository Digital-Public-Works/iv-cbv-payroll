import { vi, describe, afterEach, it, expect } from "vitest"
import { Application } from "@hotwired/stimulus"
import FieldErrorFocusController from "@js/controllers/field_error_focus_controller.js"

async function setupController(html) {
  document.body.innerHTML = html
  // jsdom doesn't implement scrollIntoView; stub before the controller's frame fires
  const alert = document.getElementById("slim-alert")
  if (alert) alert.scrollIntoView = vi.fn()

  const application = Application.start()
  application.register("field-error-focus", FieldErrorFocusController)
  await new Promise((resolve) => setTimeout(resolve, 0))
  // let the controller's requestAnimationFrame (queued on connect) run
  await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)))

  return application
}

describe("field_error_focus_controller", () => {
  let application

  afterEach(() => {
    application?.stop()
    document.body.innerHTML = ""
    vi.restoreAllMocks()
  })

  it("scrolls the alert into view and focuses the first control", async () => {
    application = await setupController(`
      <div id="slim-alert">You must select an answer to continue.</div>
      <fieldset data-controller="field-error-focus"
                data-field-error-focus-alert-id-value="slim-alert">
        <input type="radio" id="yes" name="answer" aria-invalid="true" aria-describedby="slim-alert" />
        <input type="radio" id="no" name="answer" aria-invalid="true" aria-describedby="slim-alert" />
      </fieldset>
    `)

    const alert = document.getElementById("slim-alert")
    expect(alert.scrollIntoView).toHaveBeenCalledWith({ block: "start" })
    expect(document.activeElement).toBe(document.getElementById("yes"))
  })

  it("still focuses the control when the alert is missing", async () => {
    application = await setupController(`
      <fieldset data-controller="field-error-focus"
                data-field-error-focus-alert-id-value="slim-alert">
        <input type="radio" id="yes" name="answer" />
      </fieldset>
    `)

    expect(document.activeElement).toBe(document.getElementById("yes"))
  })
})
