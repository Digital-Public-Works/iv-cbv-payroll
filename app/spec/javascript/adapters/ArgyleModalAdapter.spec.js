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
  mockErrorOpenedEvent,
  mockLinkClosedEvent,
  mockUnknownArgyleEvent,
  mockLoginHelpClickedEvent,
  mockSuccessOpenedEvent,
  mockAccountStatusOpenedEvent,
  mockAccountStatusDisconnectedEvent,
} from "@test/fixtures/argyle.fixture.js"
import { mockApplicantEncounteredArgyleInvalidCredentialsLoginError } from "@test/fixtures/mockApplicantEncounteredArgyleInvalidCredentialsLoginError.js"

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
  afterEach(() => {})

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
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantClosedArgyleModal")
    })
    it("triggers the provided onExit callback when modal throws error", async () => {
      await triggers.triggerError()
      expect(modalAdapterArgs.onExit).toHaveBeenCalled()
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantEncounteredArgyleError")
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
      expect(trackUserAction.mock.calls[1][1]["argyle.connectionErrorCode"]).toBe(
        "invalid_credentials"
      )
      expect(trackUserAction.mock.calls[1][1]["argyle.connectionStatus"]).toBe("error")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantEncounteredArgyleMfaError for account error with MFA error code", async () => {
      await triggers.triggerUIEvent(mockAccountErrorMfaError)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantEncounteredArgyleMfaError")
      expect(trackUserAction.mock.calls[1][1]["argyle.connectionErrorCode"]).toBe("mfa_timeout")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantEncounteredArgylePlatformError for account error with platform error code", async () => {
      await triggers.triggerUIEvent(mockAccountErrorPlatformError)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantEncounteredArgylePlatformError")
      expect(trackUserAction.mock.calls[1][1]["argyle.connectionErrorCode"]).toBe(
        "platform_unavailable"
      )
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantEncounteredArgyleAccountStateError for account error with account issue code", async () => {
      await triggers.triggerUIEvent(mockAccountErrorAccountIssueError)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantEncounteredArgyleAccountStateError")
      expect(trackUserAction.mock.calls[1][1]["argyle.connectionErrorCode"]).toBe(
        "account_not_found"
      )
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantEncounteredArgyleCredentialError for account error with credential error code", async () => {
      await triggers.triggerUIEvent(mockAccountErrorCredentialError)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantEncounteredArgyleCredentialError")
      expect(trackUserAction.mock.calls[1][1]["argyle.connectionErrorCode"]).toBe(
        "invalid_employer_identifier"
      )
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantEncounteredArgyleLimitError for account error with limit error code", async () => {
      await triggers.triggerUIEvent(mockAccountErrorLimitError)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantEncounteredArgyleLimitError")
      expect(trackUserAction.mock.calls[1][1]["argyle.connectionErrorCode"]).toBe(
        "login_attempts_exceeded"
      )
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantEncounteredArgyleUnknownError for account error with system error code", async () => {
      await triggers.triggerUIEvent(mockAccountErrorSystemError)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantEncounteredArgyleUnknownError")
      expect(trackUserAction.mock.calls[1][1]["argyle.connectionErrorCode"]).toBe("system_error")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })
    it("logs ApplicantEncounteredArgyleUndefinedAccountError for account error with no error code", async () => {
      await triggers.triggerUIEvent(mockAccountErrorNoCode)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe(
        "ApplicantEncounteredArgyleUndefinedAccountError"
      )
      expect(trackUserAction.mock.calls[1][1]["argyle.connectionErrorCode"]).toBeUndefined()
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })

    // New "error - opened" event test
    // Per Argyle docs: error - opened uses errorType, not errorCode
    it("logs ApplicantEncounteredArgyleSystemError for error opened event", async () => {
      await triggers.triggerUIEvent(mockErrorOpenedEvent)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantEncounteredArgyleSystemError")
      expect(trackUserAction.mock.calls[1][1]["argyle.errorType"]).toBe("invalid_user_token")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
    })

    // New "link closed" event test
    it("logs ApplicantClosedArgyleLinkFromErrorScreen for link closed event", async () => {
      await triggers.triggerUIEvent(mockLinkClosedEvent)
      expect(trackUserAction).toHaveBeenCalledTimes(2)
      expect(trackUserAction.mock.calls[1][0]).toBe("ApplicantClosedArgyleLinkFromErrorScreen")
      expect(trackUserAction.mock.calls[1][1]).toMatchSnapshot()
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
})
