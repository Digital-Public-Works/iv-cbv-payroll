import { Controller } from "@hotwired/stimulus"
import { trackUserAction } from "@js/utilities/api.js"

export default class extends Controller {
  connect() {
  }

  disconnect() {
  }

  back() {
    trackUserAction("ApplicantClickedBackButton", { from_page: window.location.pathname })
    window.history.back()
  }
}
