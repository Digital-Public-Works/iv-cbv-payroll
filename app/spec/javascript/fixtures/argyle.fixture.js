import { vi, describe, beforeEach, it, expect } from "vitest"
import loadScript from "load-script"

export const mockArgyleAuthToken = { user: { user_token: "test-token" }, isSandbox: true }
export const mockArgyleAccountData = { accountId: "account-id", platformId: "platform-id" }
export const mockArgyleSearchOpenedEvent = { name: "search - opened" }
export const mockApplicantEncounteredArgyleAuthRequiredLoginError = {
  name: "login - opened",
  properties: { errorCode: "auth_required" },
}
export const mockApplicantEncounteredArgyleConnectionUnavailableLoginError = {
  name: "login - opened",
  properties: { errorCode: "connection_unavailable" },
}
export const mockApplicantEncounteredArgyleExpiredCredentialsLoginError = {
  name: "login - opened",
  properties: { errorCode: "expired_credentials" },
}
export const mockApplicantEncounteredArgyleInvalidAuthLoginError = {
  name: "login - opened",
  properties: { errorCode: "invalid_auth" },
}
export const mockApplicantEncounteredArgyleInvalidCredentialsLoginError = {
  name: "login - opened",
  properties: { errorCode: "invalid_credentials" },
}
export const mockApplicantEncounteredArgyleMfaCanceledLoginError = {
  name: "login - opened",
  properties: { errorCode: "mfa_cancelled_by_the_user" },
}
export const mockApplicantViewedArgyleLoginPage = {
  name: "login - opened",
  properties: { errorCode: "other" },
}
export const mockApplicantViewedArgyleProviderConfirmation = { name: "search - link item selected" }
export const mockApplicantUpdatedArgyleSearchTerm = {
  name: "search - term updated",
  term: "search term",
  tab: "tab",
  properties: { term: "search term", tab: "tab" },
}
export const mockApplicantAttemptedArgyleLogin = { name: "login - form submitted" }
export const mockApplicantAccessedArgyleModalMFAScreen = { name: "mfa - opened" }

// New "account error - opened" event mocks (one per category)
export const mockAccountErrorAuthenticationError = {
  name: "account error - opened",
  properties: {
    errorCode: "invalid_credentials",
    errorMessage: "Invalid credentials",
    userId: "test-user-id",
  },
}
export const mockAccountErrorMfaError = {
  name: "account error - opened",
  properties: { errorCode: "mfa_timeout", errorMessage: "MFA timeout", userId: "test-user-id" },
}
export const mockAccountErrorPlatformError = {
  name: "account error - opened",
  properties: {
    errorCode: "platform_unavailable",
    errorMessage: "Platform unavailable",
    userId: "test-user-id",
  },
}
export const mockAccountErrorAccountIssueError = {
  name: "account error - opened",
  properties: {
    errorCode: "account_not_found",
    errorMessage: "Account not found",
    userId: "test-user-id",
  },
}
export const mockAccountErrorCredentialError = {
  name: "account error - opened",
  properties: {
    errorCode: "invalid_employer_identifier",
    errorMessage: "Invalid employer",
    userId: "test-user-id",
  },
}
export const mockAccountErrorLimitError = {
  name: "account error - opened",
  properties: {
    errorCode: "login_attempts_exceeded",
    errorMessage: "Too many attempts",
    userId: "test-user-id",
  },
}
export const mockAccountErrorSystemError = {
  name: "account error - opened",
  properties: { errorCode: "system_error", errorMessage: "System error", userId: "test-user-id" },
}
export const mockAccountErrorNoCode = {
  name: "account error - opened",
  properties: { errorMessage: "Unknown error", userId: "test-user-id" },
}

// New "error - opened" event mock
export const mockErrorOpenedEvent = {
  name: "error - opened",
  properties: {
    errorCode: "invalid_user_token",
    errorMessage: "Invalid user token",
    userId: "test-user-id",
  },
}

// New "link closed" event mock
export const mockLinkClosedEvent = {
  name: "link closed",
  properties: { userId: "test-user-id" },
}

// Unknown event mock
export const mockUnknownArgyleEvent = {
  name: "some-future-event",
  properties: { userId: "test-user-id", someNewProperty: "value" },
}

const triggers = ({
  onAccountConnected,
  onClose,
  onAccountCreated,
  onAccountError,
  onAccountRemoved,
  onTokenExpired,
  onError,
  onUIEvent,
}) => ({
  triggerAccountConnected: () => onAccountConnected && onAccountConnected(mockArgyleAccountData),
  triggerClose: () => onClose && onClose(),
  triggerAccountCreated: () => onAccountCreated && onAccountCreated(mockArgyleAccountData),
  triggerAccountError: () => onAccountError && onAccountError(mockArgyleAccountData),
  triggerAccountRemoved: () => onAccountRemoved && onAccountRemoved(mockArgyleAccountData),
  triggerError: () => onError && onError(),
  triggerTokenExpired: (cb) => onTokenExpired && onTokenExpired(cb),
  triggerUIEvent: (payload) => onUIEvent && onUIEvent(payload),
})

export const mockArgyleModule = {
  create: vi.fn((createParams) => {
    return {
      open: vi.fn(() => triggers(createParams)),
    }
  }),
}

export const mockArgyle = () => {
  loadScript.mockImplementation((url, callback) => {
    vi.stubGlobal("Argyle", mockArgyleModule)
    callback(null, global.Argyle)
  })
}
