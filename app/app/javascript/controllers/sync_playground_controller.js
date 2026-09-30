import { Controller } from "@hotwired/stimulus"
import CSRF from "../utilities/csrf"

// Dev-only controls for /cbv/preview/sync_playground.
// Webhooks are sent with fetch (not a Turbo form, which disables the submit button
// while in flight and drops focus to <body>), so the clicked button keeps focus.
// A sent button switches from the outline style to the default (filled) style.
export default class extends Controller {
  static targets = ["polling"]
  static values = { webhookUrl: String, realPollUrl: String, playgroundPollUrl: String }

  sendWebhook(event) {
    event.currentTarget.classList.remove("usa-button--outline")

    const body = new FormData()
    body.append("event", event.params.event)

    return fetch(this.webhookUrlValue, {
      method: "POST",
      headers: { Accept: "text/vnd.turbo-stream.html", "X-CSRF-Token": CSRF.token },
      body,
    })
      .then((response) => response.text())
      .then((html) => Turbo.renderStreamMessage(html))
  }

  // Swaps the polling URL live (the polling controller reads urlValue on every tick)
  // and mirrors the setting in the address bar so a reload keeps it.
  toggleRedirect(event) {
    const redirect = event.currentTarget.checked
    this.pollingTarget.setAttribute(
      "data-polling-url-value",
      redirect ? this.realPollUrlValue : this.playgroundPollUrlValue
    )

    const url = new URL(window.location.href)
    if (redirect) {
      url.searchParams.delete("redirect")
    } else {
      url.searchParams.set("redirect", "0")
    }
    window.history.replaceState(window.history.state, "", url)
  }
}
