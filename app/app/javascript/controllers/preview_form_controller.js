import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    console.log("PreviewFormController connected")
    console.log("hihih")
  }

  submit() {
    console.log("PreviewFormController submit called")
    this.element.requestSubmit()
  }
}
