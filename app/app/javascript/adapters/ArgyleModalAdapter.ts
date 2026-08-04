import { trackUserAction, fetchArgyleToken } from "@js/utilities/api.js"
import { getDocumentLocale } from "@js/utilities/getDocumentLocale.js"
import { ModalAdapter } from "./ModalAdapter.js"
import {
  argyleUIEventToTrackingName,
  isArgyleErrorEvent,
  namespaceTrackingProperties,
} from "./argyleTracking.js"
import {
  onceElementAppears,
  containBackgroundFocus,
} from "@js/utilities/modalBackgroundContainment.js"
import { describeElement } from "@js/utilities/modalFocusContainment.js"

const ARGYLE_ROOT_SELECTOR = 'div[id*="argyle-link-root"]'

export default class ArgyleModalAdapter extends ModalAdapter {
  private seenError = false
  private cancelBackgroundContainment?: () => void
  private releaseBackgroundContainment?: () => void
  private cancelInitialFocus?: () => void
  private argyleLink?: ReturnType<Argyle["create"]>

  private onEscapeKeydown = (event: KeyboardEvent) => {
    if (event.key !== "Escape") return
    this.argyleLink?.close()
  }

  // Covers both onClose and onError, which already funnel into this. Must
  // wait for the exit callback (which re-enables the trigger button) to run
  // before restoring focus - a disabled button silently rejects .focus().
  async onExit(eventPayload: any = {}) {
    console.log("[ArgyleModalAdapter] onExit() entered, state at entry:", {
      triggerElement: describeElement(this.triggerElement),
      fallbackFocusElement: describeElement(this.fallbackFocusElement),
      eventPayload,
    })

    // Un-inert the background before restoring focus below: an inert
    // element can't receive .focus(), so this must happen first or focus
    // restoration silently no-ops.
    this.cancelBackgroundContainment?.()
    this.releaseBackgroundContainment?.()
    this.cancelInitialFocus?.()
    document.removeEventListener("keydown", this.onEscapeKeydown)

    await super.onExit(eventPayload)

    console.log("[ArgyleModalAdapter] onExit() about to restoreFocus(), state now:", {
      triggerElement: describeElement(this.triggerElement),
      fallbackFocusElement: describeElement(this.fallbackFocusElement),
    })
    this.restoreFocus()
  }

  async open() {
    const locale = getDocumentLocale()

    if (this.requestData) {
      await trackUserAction("ApplicantSelectedEmployerOrPlatformItem", {
        item_type: this.requestData.responseType,
        item_id: this.requestData.id,
        item_name: this.requestData.name,
        is_default_option: this.requestData.isDefaultOption,
        provider_name: this.requestData.providerName,
        locale,
      })

      const { user, isSandbox, flowId } = await fetchArgyleToken(this.requestData.id)

      this.cancelBackgroundContainment = onceElementAppears(ARGYLE_ROOT_SELECTOR, (root) => {
        this.releaseBackgroundContainment = containBackgroundFocus(root)
      })

      // Places focus once, the first time the widget's root appears -
      // deliberately not on every internal Argyle screen transition
      // (intro -> search -> login -> MFA etc.), which would fight the
      // widget's own focus handling once the user is already inside it.
      this.cancelInitialFocus = onceElementAppears(ARGYLE_ROOT_SELECTOR, (root) => {
        root.setAttribute("tabindex", "-1")
        root.focus()
        // tabindex is only needed transiently to make the initial .focus()
        // above work. Left in place, it makes the root a permanent focus
        // target: whenever Argyle re-renders internally and removes
        // whatever's currently focused (e.g. its own exit/X button), the
        // browser's "move focus to nearest focusable ancestor" behavior
        // lands on this div instead of falling through to <body> - and
        // since it's a real element (not <body>), the existing guardFocus
        // restoration logic treats that as a legitimate focus change and
        // stops correcting it, permanently stranding focus here.
        root.removeAttribute("tabindex")
      })

      this.argyleLink = (this.modalSdk as Argyle).create({
        userToken: user.user_token,
        flowId: flowId,
        items: [this.requestData.id],
        language: locale,
        onAccountConnected: this.onSuccess.bind(this),
        onTokenExpired: this.onTokenExpired.bind(this),
        onAccountCreated: async (payload) => {
          await trackUserAction(
            "ApplicantCreatedArgyleAccount",
            namespaceTrackingProperties(payload)
          )
        },
        onAccountError: async (payload) => {
          await trackUserAction(
            "ApplicantEncounteredArgyleAccountCallbackError",
            namespaceTrackingProperties(payload)
          )
        },
        onAccountRemoved: async (payload) => {
          await trackUserAction(
            "ApplicantRemovedArgyleAccount",
            namespaceTrackingProperties(payload)
          )
        },
        onUIEvent: async (payload) => {
          await this.onUIEvent(payload)
        },
        onClose: this.onClose.bind(this),
        onError: this.onError.bind(this),
        sandbox: isSandbox,
      })
      document.addEventListener("keydown", this.onEscapeKeydown)
      return this.argyleLink.open()
    } else {
      // TODO this should throw an error, which should be caught by a document.onerror handler to show the user a crash message.
      await trackUserAction("ApplicantEncounteredModalAdapterError", {
        message: "Missing requestData from init() function",
      })
      await this.onExit()
    }
  }

  async onError(err: LinkError) {
    await trackUserAction("ApplicantEncounteredArgyleError", err)
    await this.onExit()
  }

  async onClose() {
    await trackUserAction("ApplicantClosedArgyleModal")
    await this.onExit()
  }

  async onUIEvent(payload: ArgyleUIEvent) {
    if (isArgyleErrorEvent(payload)) {
      this.seenError = true
    } else if (payload.name === "success - opened") {
      this.seenError = false
    }

    if (payload.name === "link closed" && !this.seenError) {
      return
    }

    await trackUserAction(argyleUIEventToTrackingName(payload), {
      "argyle.eventName": payload.name,
      ...namespaceTrackingProperties(payload.properties),
    })
  }

  async onSuccess(eventPayload: ArgyleAccountData) {
    await trackUserAction("ApplicantSucceededWithArgyleLogin", {
      account_id: eventPayload.accountId,
      argyle_user_id: eventPayload.userId,
      item_id: eventPayload.itemId,
      payload: eventPayload,
    })

    if (this.successCallback) {
      this.successCallback(eventPayload.accountId)
    }
  }

  async onTokenExpired(updateToken: Function) {
    await trackUserAction("ApplicantEncounteredArgyleTokenExpired")
    const { user } = await fetchArgyleToken()
    updateToken(user.user_token)
  }
}
