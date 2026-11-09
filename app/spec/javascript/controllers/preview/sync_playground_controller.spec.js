import { vi, describe, beforeEach, afterEach, it, expect } from "vitest"
import { Application } from "@hotwired/stimulus"
import SyncPlaygroundController from "@js/controllers/preview/sync_playground_controller"

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0))

describe("SyncPlaygroundController", () => {
  let application

  beforeEach(async () => {
    document.body.innerHTML = `
      <div data-controller="sync-playground"
           data-sync-playground-webhook-url-value="/webhook"
           data-sync-playground-real-poll-url-value="/real"
           data-sync-playground-playground-poll-url-value="/playground">
        <div data-sync-playground-target="polling" data-polling-url-value="/real"></div>
        <button type="button" id="send" class="usa-button usa-button--outline"
                data-action="sync-playground#sendWebhook"
                data-sync-playground-event-param="identities.added">Send</button>
        <input type="checkbox" id="redirect" checked
               data-action="change->sync-playground#toggleRedirect">
      </div>
    `
    global.Turbo = { renderStreamMessage: vi.fn() }
    fetch.mockResolvedValue({ text: () => Promise.resolve("<turbo-stream></turbo-stream>") })

    application = Application.start()
    application.register("sync-playground", SyncPlaygroundController)
    await flushPromises()
  })

  afterEach(() => {
    application.stop()
    fetch.mockReset()
    delete global.Turbo
  })

  it("posts the event, renders the stream response, and keeps focus on the button", async () => {
    const button = document.getElementById("send")
    button.focus()
    button.click()
    await flushPromises()

    const [url, options] = fetch.mock.calls[0]
    expect(url).toBe("/webhook")
    expect(options.method).toBe("POST")
    expect(options.body.get("event")).toBe("identities.added")
    expect(Turbo.renderStreamMessage).toHaveBeenCalledWith("<turbo-stream></turbo-stream>")
    expect(button.disabled).toBe(false)
    expect(document.activeElement).toBe(button)
    expect(button.classList.contains("usa-button--outline")).toBe(false)
    expect(button.classList.contains("usa-button")).toBe(true)
  })

  it("swaps the polling URL and the ?redirect param when the redirect checkbox changes", () => {
    const checkbox = document.getElementById("redirect")
    const polling = document.querySelector("[data-sync-playground-target='polling']")
    const replaceState = vi.spyOn(window.history, "replaceState").mockImplementation(() => {})

    checkbox.checked = false
    checkbox.dispatchEvent(new Event("change"))
    expect(polling.getAttribute("data-polling-url-value")).toBe("/playground")
    expect(replaceState.mock.calls.at(-1)[2].searchParams.get("redirect")).toBe("0")

    checkbox.checked = true
    checkbox.dispatchEvent(new Event("change"))
    expect(polling.getAttribute("data-polling-url-value")).toBe("/real")
    expect(replaceState.mock.calls.at(-1)[2].searchParams.has("redirect")).toBe(false)

    replaceState.mockRestore()
  })
})
