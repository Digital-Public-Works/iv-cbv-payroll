import { vi, describe, beforeEach, afterEach, it, expect } from "vitest"
import loadScript from "load-script"
import ArgyleModalAdapter from "@js/adapters/ArgyleModalAdapter"
import { fetchArgyleToken, trackUserAction } from "@js/utilities/api"
import { mockArgyle, mockArgyleAuthToken } from "@test/fixtures/argyle.fixture"
import { loadArgyleResource } from "@js/utilities/loadProviderResources.ts"
import {
  mockArgyleSearchOpenedEvent,
  mockApplicantEncounteredArgyleAuthRequiredLoginError,
  mockApplicantEncounteredArgyleConnectionUnavailableLoginError,
  mockApplicantEncounteredArgyleExpiredCredentialsLoginError,
  mockApplicantEncounteredArgyleInvalidAuthLoginError,
  mockApplicantEncounteredArgyleInvalidCredentialsLoginError,
  mockApplicantEncounteredArgyleMfaCanceledLoginError,
  mockApplicantViewedArgyleLoginPage,
  mockApplicantViewedArgyleProviderConfirmation,
  mockApplicantUpdatedArgyleSearchTerm,
  mockApplicantAttemptedArgyleLogin,
  mockApplicantAccessedArgyleModalMFAScreen,
  mockAccountErrorAuthenticationError,
  mockAccountErrorMfaError,
  mockAccountErrorPlatformError,
  mockAccountErrorAccountIssueError,
  mockAccountErrorCredentialError,
  mockAccountErrorLimitError,
  mockAccountErrorSystemError,
  mockAccountErrorNoCode,
  mockAccountErrorConnectionPendingConnecting,
  mockAccountErrorConnectionPendingAwaitingUserAction,
  mockAccountErrorConnectionPendingUpdating,
  mockErrorOpenedEvent,
  mockLinkClosedEvent,
  mockUnknownArgyleEvent,
  mockLoginHelpClickedEvent,
  mockSuccessOpenedEvent,
  mockAccountStatusOpenedEvent,
  mockAccountStatusDisconnectedEvent,
} from "@test/fixtures/argyle.fixture.js"

const modalAdapterArgs = {
  onSuccess: vi.fn(),
  onExit: vi.fn(),
  requestData: {
    responseType: "response-type",
    id: "id",
    providerName: "pinwheel",
    name: "test-name",
    isDefaultOption: true,
  },
}

describe("ArgyleModalAdapter", () => {
  let adapter
  let triggers

  beforeEach(async () => {
    vi.useFakeTimers()
    mockArgyle()
    await loadArgyleResource()
    adapter = new ArgyleModalAdapter(Argyle)
    adapter.init(modalAdapterArgs)
    triggers = await adapter.open()
  })
  afterEach(() => {
    // Most tests here never close the modal, so the MutationObserver
    // `open()` sets up to watch for the Argyle root div is otherwise left
    // dangling on document.body and fires again for whatever the *next*
    // test appends to it.
    adapter.cancelBackgroundContainment?.()
    adapter.cancelInitialFocus?.()
    document.removeEventListener("keydown", adapter.onEscapeKeydown)
  })

  describe("open", () => {
    it("calls track user action", async () => {
      expect(trackUserAction).toHaveBeenCalled()
      expect(trackUserAction.mock.calls[0][0]).toBe("ApplicantSelectedEmployerOrPlatformItem")
      expect(trackUserAction.mock.calls[0]).toMatchSnapshot()
    })
    it("fetches token successfully", async () => {
      expect(fetchArgyleToken).toHaveBeenCalledTimes(1)
      expect(fetchArgyleToken).toHaveResolvedWith(mockArgyleAuthToken)
    })
    it("opens argyle modal", async () => {
      expect(Argyle.create).toHaveBeenCalledTimes(1)
    })
    it("passes sandbox flag from token response", async () => {
      expect(Argyle.create).toHaveBeenCalledWith(
        expect.objectContaining({
          sandbox: mockArgyleAuthToken.isSandbox,
        })
      )
      expect(mockArgyleAuthToken.isSandbox).toBe(true)
    })
    it("passes the current document locale as the language param", async () => {
      expect(Argyle.create).toHaveBeenCalledWith(
        expect.objectContaining({
          language: "en",
        })
      )
    })
    it("passes 'es' as the language param when the document locale is Spanish", async () => {
      const previousLang = document.documentElement.lang
      document.documentElement.lang = "es"
      try {
        Argyle.create.mockClear()
        const esAdapter = new ArgyleModalAdapter(Argyle)
        esAdapter.init(modalAdapterArgs)
        await esAdapter.open()
        // Otherwise its background-containment/initial-focus MutationObservers
        // and Escape keydown listener keep watching document for the rest of
        // the file's test run.
        esAdapter.cancelBackgroundContainment?.()
        esAdapter.cancelInitialFocus?.()
        document.removeEventListener("keydown", esAdapter.onEscapeKeydown)
        expect(Argyle.create).toHaveBeenCalledTimes(1)
        expect(Argyle.create).toHaveBeenCalledWith(
          expect.objectContaining({
            language: "es",
          })
        )
      } finally {
        document.documentElement.lang = previousLang
      }
    })
  })

  describe("event:onSuccess", () => {
    it("calls track user action", async () => {
      await triggers.triggerAccountConnected()
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantSucceededWithArgyleLogin")
    })
    it("triggers the modal adapter onSuccess callback", async () => {
      await triggers.triggerAccountConnected()
      expect(modalAdapterArgs.onSuccess).toHaveBeenCalled()
    })
  })
  describe("event:onExit", () => {
    it("triggers the provided onExit callback when modal closed", async () => {
      await triggers.triggerClose()
      expect(modalAdapterArgs.onExit).toHaveBeenCalled()
      expect(trackUserAction).toHaveBeenCalledTimes(3)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantClosedArgyleModal")
      // No triggerElement/fallbackFocusElement configured on this shared
      // adapter, so restoreFocus() falls back to <body> and fires the
      // diagnostic added for the demo-only "focus lost to <body>" bug report.
      expect(trackUserAction.mock.calls[2][0]).toBe("DiagnosticModalFocusFellBackToBody")
    })
    it("triggers the provided onExit callback when modal throws error", async () => {
      await triggers.triggerError()
      expect(modalAdapterArgs.onExit).toHaveBeenCalled()
      expect(trackUserAction).toHaveBeenCalledTimes(3)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantEncounteredArgyleError")
      expect(trackUserAction.mock.calls[2][0]).toBe("DiagnosticModalFocusFellBackToBody")
    })
  })

  describe("event:other", () => {
    it("logs onAccountCreated Event", async () => {
      await triggers.triggerAccountCreated()
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantCreatedArgyleAccount")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs onAccountRemoved Event", async () => {
      await triggers.triggerAccountRemoved()
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantRemovedArgyleAccount")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs onAccountError Event", async () => {
      await triggers.triggerAccountError()
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe(
        "ApplicantEncounteredArgyleAccountCallbackError"
      )
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("refreshes token onTokenExpired", async () => {
      const updateTokenMock = vi.fn()
      await triggers.triggerTokenExpired(updateTokenMock)
      expect(updateTokenMock).toHaveBeenCalledTimes(1)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantEncounteredArgyleTokenExpired")
    })
    it("logs ApplicantViewedArgyleDefaultProviderSearch Event", async () => {
      await triggers.triggerUIEvent(mockArgyleSearchOpenedEvent)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantViewedArgyleDefaultProviderSearch")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantEncounteredArgyleAuthenticationError for login with auth_required error", async () => {
      await triggers.triggerUIEvent(mockApplicantEncounteredArgyleAuthRequiredLoginError)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantEncounteredArgyleAuthenticationError")
      expect(trackUserAction.mock.calls[1][1]["argyle.errorCode"]).toBe("auth_required")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantEncounteredArgylePlatformError for login with connection_unavailable error", async () => {
      await triggers.triggerUIEvent(mockApplicantEncounteredArgyleConnectionUnavailableLoginError)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantEncounteredArgylePlatformError")
      expect(trackUserAction.mock.calls[1][1]["argyle.errorCode"]).toBe("connection_unavailable")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantEncounteredArgyleAuthenticationError for login with expired_credentials error", async () => {
      await triggers.triggerUIEvent(mockApplicantEncounteredArgyleExpiredCredentialsLoginError)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantEncounteredArgyleAuthenticationError")
      expect(trackUserAction.mock.calls[1][1]["argyle.errorCode"]).toBe("expired_credentials")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantEncounteredArgyleAuthenticationError for login with invalid_auth error", async () => {
      await triggers.triggerUIEvent(mockApplicantEncounteredArgyleInvalidAuthLoginError)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantEncounteredArgyleAuthenticationError")
      expect(trackUserAction.mock.calls[1][1]["argyle.errorCode"]).toBe("invalid_auth")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantEncounteredArgyleAuthenticationError for login with invalid_credentials error", async () => {
      await triggers.triggerUIEvent(mockApplicantEncounteredArgyleInvalidCredentialsLoginError)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantEncounteredArgyleAuthenticationError")
      expect(trackUserAction.mock.calls[1][1]["argyle.errorCode"]).toBe("invalid_credentials")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantEncounteredArgyleMfaError for login with mfa_cancelled error", async () => {
      await triggers.triggerUIEvent(mockApplicantEncounteredArgyleMfaCanceledLoginError)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantEncounteredArgyleMfaError")
      expect(trackUserAction.mock.calls[1][1]["argyle.errorCode"]).toBe("mfa_cancelled_by_the_user")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantViewedArgyleLoginPage Event", async () => {
      await triggers.triggerUIEvent(mockApplicantViewedArgyleLoginPage)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantViewedArgyleLoginPage")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantViewedArgyleProviderConfirmation Event", async () => {
      await triggers.triggerUIEvent(mockApplicantViewedArgyleProviderConfirmation)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantViewedArgyleProviderConfirmation")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantUpdatedArgyleSearchTerm Event", async () => {
      await triggers.triggerUIEvent(mockApplicantUpdatedArgyleSearchTerm)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantUpdatedArgyleSearchTerm")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantAttemptedArgyleLogin Event", async () => {
      await triggers.triggerUIEvent(mockApplicantAttemptedArgyleLogin)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantAttemptedArgyleLogin")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantAccessedArgyleModalMFAScreen Event", async () => {
      await triggers.triggerUIEvent(mockApplicantAccessedArgyleModalMFAScreen)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantAccessedArgyleModalMFAScreen")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })

    // New "account error - opened" event tests (one per error category)
    // Per Argyle docs: account error uses connectionErrorCode, not errorCode
    it("logs ApplicantEncounteredArgyleAuthenticationError for account error with auth error code", async () => {
      await triggers.triggerUIEvent(mockAccountErrorAuthenticationError)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantEncounteredArgyleAuthenticationError")
      expect(trackUserAction.mock.calls[1][1]["argyle.errorCode"]).toBe("invalid_credentials")
      expect(trackUserAction.mock.calls[1][1]["argyle.connectionStatus"]).toBe("error")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantEncounteredArgyleMfaError for account error with MFA error code", async () => {
      await triggers.triggerUIEvent(mockAccountErrorMfaError)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantEncounteredArgyleMfaError")
      expect(trackUserAction.mock.calls[1][1]["argyle.errorCode"]).toBe("mfa_timeout")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantEncounteredArgylePlatformError for account error with platform error code", async () => {
      await triggers.triggerUIEvent(mockAccountErrorPlatformError)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantEncounteredArgylePlatformError")
      expect(trackUserAction.mock.calls[1][1]["argyle.errorCode"]).toBe("platform_unavailable")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantEncounteredArgyleAccountStateError for account error with account issue code", async () => {
      await triggers.triggerUIEvent(mockAccountErrorAccountIssueError)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantEncounteredArgyleAccountStateError")
      expect(trackUserAction.mock.calls[1][1]["argyle.errorCode"]).toBe("account_not_found")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantEncounteredArgyleCredentialError for account error with credential error code", async () => {
      await triggers.triggerUIEvent(mockAccountErrorCredentialError)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantEncounteredArgyleCredentialError")
      expect(trackUserAction.mock.calls[1][1]["argyle.errorCode"]).toBe(
        "invalid_employer_identifier"
      )
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantEncounteredArgyleLimitError for account error with limit error code", async () => {
      await triggers.triggerUIEvent(mockAccountErrorLimitError)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantEncounteredArgyleLimitError")
      expect(trackUserAction.mock.calls[1][1]["argyle.errorCode"]).toBe("login_attempts_exceeded")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantEncounteredArgyleSystemError for account error with system error code", async () => {
      await triggers.triggerUIEvent(mockAccountErrorSystemError)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantEncounteredArgyleSystemError")
      expect(trackUserAction.mock.calls[1][1]["argyle.errorCode"]).toBe("system_error")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantEncounteredArgyleUndefinedAccountError for account error with no error code", async () => {
      await triggers.triggerUIEvent(mockAccountErrorNoCode)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe(
        "ApplicantEncounteredArgyleUndefinedAccountError"
      )
      expect(trackUserAction.mock.calls[1][1]["argyle.errorCode"]).toBeUndefined()
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantEncounteredArgyleConnectionPendingEvent for connectionStatus 'connecting'", async () => {
      await triggers.triggerUIEvent(mockAccountErrorConnectionPendingConnecting)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe(
        "ApplicantEncounteredArgyleConnectionPendingEvent"
      )
      expect(trackUserAction.mock.calls[1][1]["argyle.connectionStatus"]).toBe("connecting")
      expect(trackUserAction.mock.calls[1][1]["argyle.errorCode"]).toBeUndefined()
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantEncounteredArgyleConnectionPendingEvent for connectionStatus 'awaiting_user_action'", async () => {
      await triggers.triggerUIEvent(mockAccountErrorConnectionPendingAwaitingUserAction)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe(
        "ApplicantEncounteredArgyleConnectionPendingEvent"
      )
      expect(trackUserAction.mock.calls[1][1]["argyle.connectionStatus"]).toBe(
        "awaiting_user_action"
      )
      expect(trackUserAction.mock.calls[1][1]["argyle.errorCode"]).toBeUndefined()
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantEncounteredArgyleConnectionPendingEvent for connectionStatus 'updating'", async () => {
      await triggers.triggerUIEvent(mockAccountErrorConnectionPendingUpdating)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe(
        "ApplicantEncounteredArgyleConnectionPendingEvent"
      )
      expect(trackUserAction.mock.calls[1][1]["argyle.connectionStatus"]).toBe("updating")
      expect(trackUserAction.mock.calls[1][1]["argyle.errorCode"]).toBeUndefined()
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })

    // New "error - opened" event test
    // Per Argyle docs: error - opened uses errorType, not errorCode
    it("logs ApplicantEncounteredArgyleLinkOpenError for error opened event", async () => {
      await triggers.triggerUIEvent(mockErrorOpenedEvent)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantEncounteredArgyleLinkOpenError")
      expect(trackUserAction.mock.calls[1][1]["argyle.errorType"]).toBe("invalid_user_token")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })

    // "link closed" event tests
    it("does not log ApplicantClosedArgyleLinkFromErrorScreen on happy-path close", async () => {
      await triggers.triggerUIEvent(mockLinkClosedEvent)
      expect(trackUserAction).not.toHaveBeenCalledWith(
        "ApplicantClosedArgyleLinkFromErrorScreen",
        expect.anything()
      )
    })
    it("logs ApplicantClosedArgyleLinkFromErrorScreen when closed after link error screen", async () => {
      await triggers.triggerUIEvent(mockErrorOpenedEvent)
      await triggers.triggerUIEvent(mockLinkClosedEvent)
      expect(trackUserAction).toHaveBeenCalledTimes(3)
      expect(trackUserAction.mock.calls[2][0]).toBe("ApplicantClosedArgyleLinkFromErrorScreen")
      expect(trackUserAction.mock.calls[2][1]).toMatchSnapshot()
    })
    it("logs ApplicantClosedArgyleLinkFromErrorScreen when closed after account error screen", async () => {
      await triggers.triggerUIEvent(mockAccountErrorAuthenticationError)
      await triggers.triggerUIEvent(mockLinkClosedEvent)
      expect(trackUserAction).toHaveBeenCalledTimes(3)
      expect(trackUserAction.mock.calls[2][0]).toBe("ApplicantClosedArgyleLinkFromErrorScreen")
    })
    it("logs ApplicantClosedArgyleLinkFromErrorScreen when closed after login error", async () => {
      await triggers.triggerUIEvent(mockApplicantEncounteredArgyleAuthRequiredLoginError)
      await triggers.triggerUIEvent(mockLinkClosedEvent)
      expect(trackUserAction).toHaveBeenCalledTimes(3)
      expect(trackUserAction.mock.calls[2][0]).toBe("ApplicantClosedArgyleLinkFromErrorScreen")
    })
    it("does not log ApplicantClosedArgyleLinkFromErrorScreen when user recovered to success after error", async () => {
      await triggers.triggerUIEvent(mockErrorOpenedEvent)
      await triggers.triggerUIEvent(mockSuccessOpenedEvent)
      await triggers.triggerUIEvent(mockLinkClosedEvent)
      expect(trackUserAction).toHaveBeenCalledTimes(3)
      expect(trackUserAction.mock.calls[2][0]).not.toBe("ApplicantClosedArgyleLinkFromErrorScreen")
    })

    // Unknown event test
    it("logs ApplicantEncounteredUnknownArgyleEvent for unknown events", async () => {
      await triggers.triggerUIEvent(mockUnknownArgyleEvent)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantEncounteredUnknownArgyleEvent")
      expect(trackUserAction.mock.calls[1][1]).toMatchObject({
        "argyle.someNewProperty": "value",
      })
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })

    // User journey event tests
    it("logs ApplicantClickedArgyleLoginHelp for login help clicked event", async () => {
      await triggers.triggerUIEvent(mockLoginHelpClickedEvent)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantClickedArgyleLoginHelp")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantViewedArgyleSuccessScreen for success opened event", async () => {
      await triggers.triggerUIEvent(mockSuccessOpenedEvent)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantViewedArgyleSuccessScreen")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantViewedArgyleAccountStatus for account status opened event", async () => {
      await triggers.triggerUIEvent(mockAccountStatusOpenedEvent)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantViewedArgyleAccountStatus")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantDisconnectedArgyleAccount for account status disconnected event", async () => {
      await triggers.triggerUIEvent(mockAccountStatusDisconnectedEvent)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantDisconnectedArgyleAccount")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
  })

  // Uses its own adapter instance/args (not the shared module-level
  // `modalAdapterArgs`/`adapter`/`triggers` from the outer beforeEach) so
  // `triggerElement` doesn't leak into unrelated tests.
  describe("focus restoration", () => {
    afterEach(() => {
      document.body.innerHTML = ""
    })

    it("restores focus to the triggerElement after the modal closes", async () => {
      const trigger = document.createElement("button")
      document.body.appendChild(trigger)

      const localAdapter = new ArgyleModalAdapter(Argyle)
      localAdapter.init({ ...modalAdapterArgs, triggerElement: trigger })
      const localTriggers = await localAdapter.open()

      await localTriggers.triggerClose()

      expect(document.activeElement).toBe(trigger)
    })

    it("restores focus to the triggerElement after the modal errors", async () => {
      const trigger = document.createElement("button")
      document.body.appendChild(trigger)

      const localAdapter = new ArgyleModalAdapter(Argyle)
      localAdapter.init({ ...modalAdapterArgs, triggerElement: trigger })
      const localTriggers = await localAdapter.open()

      await localTriggers.triggerError()

      expect(document.activeElement).toBe(trigger)
    })

    it("falls back to fallbackFocusElement when the trigger was removed before the modal closed", async () => {
      const trigger = document.createElement("button")
      const fallback = document.createElement("h1")
      fallback.setAttribute("tabindex", "-1")
      document.body.append(trigger, fallback)

      const localAdapter = new ArgyleModalAdapter(Argyle)
      localAdapter.init({
        ...modalAdapterArgs,
        triggerElement: trigger,
        fallbackFocusElement: fallback,
      })
      const localTriggers = await localAdapter.open()

      trigger.remove()
      await localTriggers.triggerClose()

      expect(document.activeElement).toBe(fallback)
    })
  })

  // Uses its own adapter instance/args, same rationale as "focus restoration"
  // above.
  describe("background containment", () => {
    beforeEach(() => {
      // The outer beforeEach's shared `adapter` is also watching
      // document.body for an Argyle root div - disconnect it first so it
      // doesn't race the local adapter under test below for ownership of
      // containing/releasing the same elements.
      adapter.cancelBackgroundContainment?.()
      adapter.cancelInitialFocus?.()
    })

    afterEach(() => {
      document.body.innerHTML = ""
    })

    it("inerts the rest of the page once the Argyle root appears, and releases it once the modal closes", async () => {
      const trigger = document.createElement("button")
      document.body.appendChild(trigger)

      const localAdapter = new ArgyleModalAdapter(Argyle)
      localAdapter.init({ ...modalAdapterArgs, triggerElement: trigger })
      const localTriggers = await localAdapter.open()

      // The real Argyle widget appends its root div to document.body once
      // it's ready - the mock SDK doesn't touch the DOM, so simulate that.
      const argyleRoot = document.createElement("div")
      argyleRoot.id = "argyle-link-root-abc123"
      document.body.appendChild(argyleRoot)
      await Promise.resolve()

      expect(trigger.inert).toBe(true)
      expect(argyleRoot.inert).toBeFalsy()

      await localTriggers.triggerClose()

      expect(trigger.inert).toBe(false)
    })

    it("does not inert the page if the Argyle root never appears (e.g. the modal errors before rendering)", async () => {
      const trigger = document.createElement("button")
      document.body.appendChild(trigger)

      const localAdapter = new ArgyleModalAdapter(Argyle)
      localAdapter.init({ ...modalAdapterArgs, triggerElement: trigger })
      const localTriggers = await localAdapter.open()

      await localTriggers.triggerError()

      expect(trigger.inert).toBeFalsy()
    })
  })

  // Uses its own adapter instance/args, same rationale as "focus restoration"
  // above.
  describe("initial focus", () => {
    beforeEach(() => {
      // See "background containment" above - the shared `adapter` from the
      // outer beforeEach would otherwise race the local adapter under test.
      adapter.cancelBackgroundContainment?.()
      adapter.cancelInitialFocus?.()
    })

    afterEach(() => {
      document.body.innerHTML = ""
    })

    it("moves focus into the Argyle root once it appears", async () => {
      const trigger = document.createElement("button")
      document.body.appendChild(trigger)
      trigger.focus()

      const localAdapter = new ArgyleModalAdapter(Argyle)
      localAdapter.init({ ...modalAdapterArgs, triggerElement: trigger })
      await localAdapter.open()

      const argyleRoot = document.createElement("div")
      argyleRoot.id = "argyle-link-root-abc123"
      document.body.appendChild(argyleRoot)
      await Promise.resolve()

      expect(document.activeElement).toBe(argyleRoot)
      // tabindex is only needed transiently to make focus() work - left in
      // place, it would make the root a permanent focus target and break
      // the existing guardFocus fallback-to-<body> restoration logic.
      expect(argyleRoot.hasAttribute("tabindex")).toBe(false)
    })
  })

  describe("Escape key", () => {
    // The keydown listener calls the SDK's close(), which (per the mock)
    // fires the real onClose -> onExit async callback chain - dispatchEvent
    // itself doesn't expose that chain to await on, so give it a few
    // microtask turns to settle instead.
    function flushPromises() {
      return Promise.resolve().then().then().then().then()
    }

    it("closes the modal when Escape is pressed", async () => {
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }))
      await flushPromises()

      expect(modalAdapterArgs.onExit).toHaveBeenCalled()
    })

    it("does not close the modal for other keys", async () => {
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter" }))
      await flushPromises()

      expect(modalAdapterArgs.onExit).not.toHaveBeenCalled()
    })

    it("stops listening for Escape once the modal has already closed", async () => {
      await triggers.triggerClose()
      modalAdapterArgs.onExit.mockClear()

      document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }))
      await flushPromises()

      expect(modalAdapterArgs.onExit).not.toHaveBeenCalled()
    })
  })
})
