import { Controller } from "@hotwired/stimulus"
import { trackUserAction } from "../utilities/api"

export default class extends Controller {
  static values = {
    page: String,
    context: Object,
  }

  track(event) {
    const element = event.currentTarget

    trackUserAction("ApplicantClickedElement", {
      element_tag_name: element.tagName.toLowerCase(),
      element_name: element.dataset.trackName,
      page: this.pageValue,
      ...this.contextValue,
    })
  }
}
