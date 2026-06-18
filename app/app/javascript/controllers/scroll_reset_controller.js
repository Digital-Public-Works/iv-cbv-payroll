import { Controller } from "@hotwired/stimulus"

/**
 * ScrollReset Controller
 *
 * Resets scroll position to top when the controller connects.
 * Use on pages that should always start at the top after Turbo navigation.
 *
 * ## Usage
 *
 * Add to a page wrapper or any element:
 *
 *   <div data-controller="scroll-reset">
 *     ...page content...
 *   </div>
 *
 * Or on the main content area:
 *
 *   <main data-controller="scroll-reset">
 */
export default class extends Controller {
  connect() {
    if (!window.location.hash) {
      window.scrollTo(0, 0)
    }
  }
}
