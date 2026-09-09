import { Controller } from "@hotwired/stimulus"

// Shows the form fields belonging to the selected communication channel.
// Each conditional group is a channelFields target carrying data-channel,
// shown only while its channel's radio is selected.
export default class extends Controller {
  static targets = ["channelFields"]

  connect() {
    this.toggle()
  }

  toggle() {
    const selected = this.element.querySelector("input[name$='[communication_channel]']:checked")

    this.channelFieldsTargets.forEach((el) => {
      el.hidden = !selected || el.dataset.channel !== selected.value
    })
  }
}
