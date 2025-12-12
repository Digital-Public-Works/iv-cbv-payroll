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
 *           data-element-type="<%= ClickTracker::ElementType::Accordion %>"
 *           data-element-name="payroll_provider_help">
 *
 *   <%= link_to "Try again", some_path,
 *         data: {
 *           action: "click->click-tracker#track",
 *           element_type: ClickTracker::ElementType::InternalLink,
 *           element_name: "try_searching_again"
 *         } %>
 *
 * - `data-action` (required): Wires up the click event
 * - `data-element-type` (optional): Element type from ClickTracker::ElementType
 *   Values: Generic (default), AnchorLink, InternalLink, ExternalLink, Button, Accordion
 * - `data-element-name` (required): Unique identifier for this element
 * - `data-track-event` (optional): Override the default event name (ApplicantClickedElement)
 *
 * ## Analytics payload
 *
 *   {
 *     element_type: "accordion",      // from data-element-type or "generic"
 *     element_tag_name: "button",     // HTML tag name
 *     element_name: "payroll_help",   // from data-element-name
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
        context["click_context." + snakeKey] = isNaN(value) ? value : Number(value)
      }
    }
    return context
  }

  track(event) {
    const element = event.currentTarget
    const eventName = element.dataset.trackEvent || "ApplicantClickedElement"

    trackUserAction(eventName, {
      "click.element_type": element.dataset.elementType || "generic",
      "click.element_tag_name": element.tagName.toLowerCase(),
      "click.element_name": element.dataset.elementName,
      "click.page": this.pageValue,
      ...this.contextData,
    })
  }
}
