import { Controller } from "@hotwired/stimulus"
import { trackUserAction } from "../utilities/api"

/**
 * ClickTracker Controller
 *
 * Tracks user clicks on interactive elements and sends analytics events.
 *
 * ## Setup (on a container element)
 *
 *   <div data-controller="click-tracker"
 *        data-click-tracker-page-value="page_name"
 *        data-context-some-key="value">
 *
 * - `data-click-tracker-page-value` (required): Page identifier for analytics
 * - `data-context-*` (optional): Additional context sent with every click event
 *   Examples: data-context-jobs-already-added="<%= count %>"
 *             data-context-user-type="applicant"
 *
 * ## Tracking an element
 *
 *   <button data-action="click->click-tracker#track"
 *           data-track-type="<%= ClickTracker::ElementType::Accordion %>"
 *           data-track-name="payroll_provider_help">
 *
 *   <%= link_to "Try again", some_path,
 *         data: {
 *           action: "click->click-tracker#track",
 *           track_type: ClickTracker::ElementType::InternalLink,
 *           track_name: "try_searching_again"
 *         } %>
 *
 * - `data-action` (required): Wires up the click event
 * - `data-track-type` (optional): Element type from ClickTracker::ElementType
 *   Values: Generic (default), AnchorLink, InternalLink, ExternalLink, Button, Accordion
 * - `data-track-name` (required): Unique identifier for this element
 *
 * ## Analytics payload
 *
 *   {
 *     element_type: "accordion",      // from data-track-type or "generic"
 *     element_tag_name: "button",     // HTML tag name
 *     element_name: "payroll_help",   // from data-track-name
 *     page: "missing_results",        // from data-click-tracker-page-value
 *     ...contextData                  // from data-context-* attributes
 *   }
 */
export default class extends Controller {
  static values = {
    page: String,
  }

  get contextData() {
    const context = {}
    // Auto-collect all data-context-* attributes on the controller element
    for (const [key, value] of Object.entries(this.element.dataset)) {
      if (key.startsWith("context")) {
        // Convert "contextJobsAlreadyAdded" to "jobs_already_added"
        const snakeKey = key
          .replace("context", "")
          .replace(/([A-Z])/g, "_$1")
          .toLowerCase()
          .replace(/^_/, "")
        context[snakeKey] = isNaN(value) ? value : Number(value)
      }
    }
    return context
  }

  track(event) {
    const element = event.currentTarget

    trackUserAction("ApplicantClickedElement", {
      element_type: element.dataset.trackType || "generic",
      element_tag_name: element.tagName.toLowerCase(),
      element_name: element.dataset.trackName,
      page: this.pageValue,
      ...this.contextData,
    })
  }
}
