import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  initialize() {
    console.log("Common controller initialized.")
  }
  
  connect() {
    console.log("Common controller connected.")
  }

  disconnect() {
    console.log("Commong controller disconnected.")
  }

  back() {
    window.history.back()
  }
}
