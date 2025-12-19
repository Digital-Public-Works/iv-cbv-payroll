import { trackUserAction, fetchArgyleToken } from "@js/utilities/api.js"
import { getDocumentLocale } from "@js/utilities/getDocumentLocale.js"
import { ModalAdapter } from "./ModalAdapter.js"
import { argyleUIEventToTrackingName, namespaceTrackingProperties } from "./argyleTracking.js"

export default class ArgyleModalAdapter extends ModalAdapter {
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
      return (this.modalSdk as Argyle)
        .create({
          userToken: user.user_token,
          flowId: flowId,
          items: [this.requestData.id],
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
        .open()
    } else {
      // TODO this should throw an error, which should be caught by a document.onerror handler to show the user a crash message.
      await trackUserAction("ApplicantEncounteredModalAdapterError", {
        message: "Missing requestData from init() function",
      })
      this.onExit()
    }
  }

  async onError(err: LinkError) {
    await trackUserAction("ApplicantEncounteredArgyleError", err)
    this.onExit()
  }

  async onClose() {
    await trackUserAction("ApplicantClosedArgyleModal")
    await this.onExit()
  }

  async onUIEvent(payload: ArgyleUIEvent) {
    await trackUserAction(
      argyleUIEventToTrackingName(payload),
      namespaceTrackingProperties(payload.properties)
    )
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
