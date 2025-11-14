import { trackUserAction, fetchArgyleToken } from "@js/utilities/api.js"
import { getDocumentLocale } from "@js/utilities/getDocumentLocale.js"
import { ModalAdapter } from "./ModalAdapter.js"

// Categorize Argyle error codes into meaningful groups for tracking
function categorizeArgyleError(errorCode?: string): string {
  if (!errorCode) return "ApplicantEncounteredArgyleSystemError"

  // Authentication Errors (7) - User credential issues
  const authErrors = new Set([
    "auth_required",
    "invalid_auth",
    "invalid_credentials",
    "expired_credentials",
    "full_auth_required",
    "tos_required",
    "unsupported_auth_type",
  ])

  // MFA Errors (8) - Multi-factor authentication issues
  const mfaErrors = new Set([
    "invalid_mfa",
    "mfa_cancelled_by_the_user",
    "mfa_timeout",
    "mfa_attempts_exceeded",
    "mfa_exhausted",
    "mfa_not_configured",
    "physical_mfa_unsupported",
    "unsupported_mfa_method",
  ])

  // Platform Errors (5) - Payroll system unavailable
  const platformErrors = new Set([
    "connection_unavailable",
    "platform_temporarily_unavailable",
    "platform_unavailable",
    "service_unavailable",
    "auth_method_temporarily_unavailable",
  ])

  // Account Errors (9) - Account state/configuration issues
  const accountErrors = new Set([
    "account_disabled",
    "account_inaccessible",
    "account_incomplete",
    "account_nonunique",
    "account_not_found",
    "duplicate_account",
    "existing_account_found",
    "multi_driver_account",
    "insufficient_account_data",
  ])

  // Credential Errors (8) - Employer/provider selection issues
  const credentialErrors = new Set([
    "invalid_account_type",
    "invalid_employer_identifier",
    "invalid_login_method",
    "invalid_login_url",
    "invalid_store_identifier",
    "unrecognized_employer_email",
    "unsupported_business_account",
    "credentials_managed_by_organization",
  ])

  // Limit Errors (6) - Rate limits and user-triggered issues
  const limitErrors = new Set([
    "all_employers_connected",
    "login_attempts_exceeded",
    "session_limit_reached",
    "trial_connections_exhausted",
    "trial_period_expired",
    "user_action_timeout",
  ])

  // Check categories and return corresponding event name
  if (authErrors.has(errorCode)) return "ApplicantEncounteredArgyleAuthenticationError"
  if (mfaErrors.has(errorCode)) return "ApplicantEncounteredArgleMfaError"
  if (platformErrors.has(errorCode)) return "ApplicantEncounteredArglePlatformError"
  if (accountErrors.has(errorCode)) return "ApplicantEncounteredArgyleAccountIssueError"
  if (credentialErrors.has(errorCode)) return "ApplicantEncounteredArgyleCredentialError"
  if (limitErrors.has(errorCode)) return "ApplicantEncounteredArgleLimitError"

  // Default to system error for unknown codes
  return "ApplicantEncounteredArgyleSystemError"
}

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
            await trackUserAction("ApplicantCreatedArgyleAccount", payload)
          },
          onAccountError: async (payload) => {
            await trackUserAction("ApplicantEncounteredArgyleAccountError", payload)
          },
          onAccountRemoved: async (payload) => {
            await trackUserAction("ApplicantRemovedArgyleAccount", payload)
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
    switch (payload.name) {
      case "search - opened":
        await trackUserAction("ApplicantViewedArgyleDefaultProviderSearch", payload)
        break
      case "account error - opened":
        {
          const eventName = categorizeArgyleError(payload.properties.errorCode)
          await trackUserAction(eventName, payload)
        }
        break
      case "error - opened":
        {
          const eventName = categorizeArgyleError(payload.properties.errorCode)
          await trackUserAction(eventName, payload)
        }
        break
      case "link closed":
        await trackUserAction("ApplicantClosedArgyleLinkFromErrorScreen", payload)
        break
      case "login - opened":
        if (payload.properties.errorCode) {
          const eventName = categorizeArgyleError(payload.properties.errorCode)
          await trackUserAction(eventName, payload)
        } else {
          await trackUserAction("ApplicantViewedArgyleLoginPage", payload)
        }
        break
      case "search - link item selected":
        await trackUserAction("ApplicantViewedArgyleProviderConfirmation", payload)
        break
      case "search - term updated":
        await trackUserAction("ApplicantUpdatedArgyleSearchTerm", {
          term: payload.properties.term,
          tab: payload.properties.tab,
          payload: payload,
        })
        break
      case "login - form submitted":
        await trackUserAction("ApplicantAttemptedArgyleLogin", payload)
        break
      case "mfa - opened":
        await trackUserAction("ApplicantAccessedArgyleModalMFAScreen", payload)
        break
      default:
        console.warn("Unknown Argyle UI event:", payload.name, payload)
        await trackUserAction("ApplicantEncounteredUnknownArgyleEvent", {
          event_name: payload.name,
          payload: payload,
        })
        break
    }
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
