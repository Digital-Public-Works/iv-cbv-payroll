import { Controller } from "@hotwired/stimulus"

/**
 * FieldErrorFocus Controller
 *
 * After a form re-renders with an error alert, scrolls the alert into view for
 * sighted users and moves focus to the first control in the field, so screen
 * readers announce the control along with its aria-describedby error.
 *
 * Rendered by `UswdsFormBuilder#radio_group` when an error_id is given:
 *
 *   <fieldset data-controller="field-error-focus"
 *             data-field-error-focus-alert-id-value="slim-alert">
 *     <input type="radio" aria-invalid="true" aria-describedby="slim-alert" ...>
 *   </fieldset>
 */
export default class extends Controller {
  static values = { alertId: String }

  connect() {
    // Wait a frame so this runs after Turbo's scroll-to-top on render.
    requestAnimationFrame(() => {
      document.getElementById(this.alertIdValue)?.scrollIntoView({ block: "start" })
      this.element.querySelector("input:not([disabled])")?.focus({ preventScroll: true })
    })
  }
}
