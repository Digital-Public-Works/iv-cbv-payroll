import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
  }

  disconnect() {
  }

  back() {
    window.history.back()
  }
}
