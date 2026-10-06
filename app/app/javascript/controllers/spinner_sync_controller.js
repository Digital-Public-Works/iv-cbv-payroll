import { Controller } from "@hotwired/stimulus"

// Keeps every sync spinner at the same rotation angle. Pinning each CSS animation's
// startTime to 0 (the document timeline's origin) makes its phase depend only on
// the shared clock, not on when the element was created, so spinners stay in step
// even if one is re-created by a poll or a Turbo navigation. With reduced motion
// there is no animation, so this is a no-op.
export default class extends Controller {
  connect() {
    if (typeof this.element.getAnimations !== "function") return

    this.element.getAnimations().forEach((animation) => {
      animation.startTime = 0
    })
  }
}
