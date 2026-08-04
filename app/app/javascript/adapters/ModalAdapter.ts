import type { RequestData, ModalAdapterArgs } from "./ModalAdapter.types.ts"
import { restoreFocusTo, describeElement } from "@js/utilities/modalFocusContainment.js"

export abstract class ModalAdapter {
  requestData?: RequestData
  successCallback?: Function
  exitCallback?: Function
  triggerElement?: HTMLElement
  fallbackFocusElement?: HTMLElement
  modalSdk: Argyle | Pinwheel

  abstract open(): void

  constructor(modalSdk: Argyle | Pinwheel) {
    this.modalSdk = modalSdk
  }

  init(args: ModalAdapterArgs) {
    console.log("[ModalAdapter] init() called with:", {
      triggerElement: describeElement(args.triggerElement),
      fallbackFocusElement: describeElement(args.fallbackFocusElement),
    })

    if (args.onSuccess) {
      this.successCallback = args.onSuccess
    }

    if (args.onExit) {
      this.exitCallback = args.onExit
    }
    if (args.requestData) {
      this.requestData = args.requestData
    }
    if (args.triggerElement) {
      this.triggerElement = args.triggerElement
    }
    if (args.fallbackFocusElement) {
      this.fallbackFocusElement = args.fallbackFocusElement
    }
  }

  restoreFocus() {
    console.log("[ModalAdapter] restoreFocus() called, current state:", {
      triggerElement: describeElement(this.triggerElement),
      fallbackFocusElement: describeElement(this.fallbackFocusElement),
    })
    restoreFocusTo(this.triggerElement, this.fallbackFocusElement)
  }

  async onExit(eventPayload: any = {}) {
    if (this.exitCallback) {
      this.exitCallback()
    }
  }

  async onSuccess(eventPayload: any) {
    if (this.successCallback) {
      this.successCallback()
    }
  }
}
