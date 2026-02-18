import { Controller } from "@hotwired/stimulus"
import { trackUserAction } from "../utilities/api.js"

export default class extends Controller {
  connect() {
    this.tracked = false
  }
  
  track() {
    if (this.tracked) {
      return
    }
    
    this.tracked = true
    trackUserAction("ApplicantClickedSearchBarTooltip")
  }
}