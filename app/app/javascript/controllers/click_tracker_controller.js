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
 * - `data-context-*` (optional): Shared context sent with every click event
 *   Examples: data-context-jobs-already-added="<%= count %>"
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
 *           element_name: "try_searching_again",
 *           context_version: "v2"
 *         } %>
 *
 * - `data-action` (required): Wires up the click event
 * - `data-element-type` (optional): Element type from ClickTracker::ElementType
 *   Values: Generic (default), AnchorLink, InternalLink, ExternalLink, Button, Accordion
 * - `data-element-name` (required): Unique identifier for this element
 * - `data-track-event` (optional): Override the default event name (ApplicantClickedElement)
 * - `data-context-*` (optional): Element-specific context (overrides controller context)
 *   Example: data-context-version="v2" data-context-from-page="missing_results"
 *
 * ## Context data precedence
 *
 * Context attributes (`data-context-*`) can be placed on either:
 * 1. The controller element - shared across all tracked elements
 * 2. The tracked element - specific to that element
 *
 * Element-level context takes precedence over controller-level context.
 *
 * ## Analytics payload
 *
 *   {
 *     element_type: "accordion",      // from data-element-type or "generic"
 *     element_tag_name: "button",     // HTML tag name
 *     element_name: "payroll_help",   // from data-element-name
 *     page: "missing_results",        // from data-click-tracker-page-value
 *     ...contextData                  // merged from controller + element data-context-*
 *   }
 */
export default class extends Controller {
  static values = {
    page: String,
  }
  transformContextData(mergedDataset) {
    const context = {}
    // Extract data-context-* attributes from merged controller + element dataset
    for (const [key, value] of Object.entries(mergedDataset)) {
      if (key.startsWith("context")) {
        // HTML: data-context-jobs-already-added (kebab-case)
        // dataset: contextJobsAlreadyAdded (browser auto-converts to camelCase)
        // output: jobs_already_added (we convert to snake_case)
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
    const combinedElementDataset = Object.assign(
      {},
      this.element.dataset,
      event.currentTarget.dataset
    )
    const eventName = combinedElementDataset.trackEvent || "ApplicantClickedElement"

    trackUserAction(eventName, {
      "click.element_tag_name": event.currentTarget.tagName.toLowerCase(),
      "click.element_type": combinedElementDataset.elementType || "generic",
      "click.element_name": combinedElementDataset.elementName,
      "click.page": this.pageValue,
      ...this.transformContextData(combinedElementDataset),
    })
  }
}
