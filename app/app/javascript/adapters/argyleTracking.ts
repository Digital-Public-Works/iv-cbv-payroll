// Namespace payload properties with "argyle." prefix for tracking
export function namespaceTrackingProperties(
  properties: Record<string, any>
): Record<string, unknown> {
  if (!properties) {
    return {}
  }
  return Object.fromEntries(
    Object.entries(properties).map(([key, value]) => {
      // Normalize connectionErrorCode to errorCode for consistent error tracking
      const normalizedKey = key === "connectionErrorCode" ? "errorCode" : key
      return [`argyle.${normalizedKey}`, value]
    })
  )
}

// Convert account error events to tracking name based on connection error code
function accountErrorToTrackingName(properties: ArgyleUIEvent["properties"]): string {
  if ("connectionErrorCode" in properties && typeof properties.connectionErrorCode === "string") {
    return argyleErrorToTrackingName(properties.connectionErrorCode)
  }
  return "ApplicantEncounteredArgyleUndefinedAccountError"
}

// Convert login events to tracking name - may be an error or successful page view
function loginEventToTrackingName(properties: ArgyleUIEvent["properties"]): string {
  if ("errorCode" in properties && typeof properties.errorCode === "string") {
    return argyleErrorToTrackingName(properties.errorCode)
  }
  return "ApplicantViewedArgyleLoginPage"
}

// Convert Argyle UI events to tracking event names
export function argyleUIEventToTrackingName(event: ArgyleUIEvent): string {
  switch (event.name) {
    case "account error - opened":
      return accountErrorToTrackingName(event.properties)
    case "login - opened":
      return loginEventToTrackingName(event.properties)
    case "search - opened":
      return "ApplicantViewedArgyleDefaultProviderSearch"
    case "error - opened":
      return "ApplicantEncounteredArgyleLinkOpenError"
    case "link closed":
      return "ApplicantClosedArgyleLinkFromErrorScreen"
    case "search - link item selected":
      return "ApplicantViewedArgyleProviderConfirmation"
    case "search - term updated":
      return "ApplicantUpdatedArgyleSearchTerm"
    case "login - form submitted":
      return "ApplicantAttemptedArgyleLogin"
    case "mfa - opened":
      return "ApplicantAccessedArgyleModalMFAScreen"
    case "login - login help clicked":
      return "ApplicantClickedArgyleLoginHelp"
    case "success - opened":
      return "ApplicantViewedArgyleSuccessScreen"
    case "account status - opened":
      return "ApplicantViewedArgyleAccountStatus"
    case "account status - disconnected":
      return "ApplicantDisconnectedArgyleAccount"
    default:
      return "ApplicantEncounteredUnknownArgyleEvent"
  }
}

// Convert Argyle error codes to tracking event names
export function argyleErrorToTrackingName(errorCode: string): string {
  switch (errorCode) {
    // Authentication Errors - User credential issues
    case "auth_required":
    case "invalid_auth":
    case "invalid_credentials":
    case "expired_credentials":
    case "full_auth_required":
    case "tos_required":
    case "unsupported_auth_type":
    case "passkey_limit_reached":
      return "ApplicantEncounteredArgyleAuthenticationError"

    // MFA Errors - Multi-factor authentication issues
    case "invalid_mfa":
    case "mfa_cancelled_by_the_user":
    case "mfa_timeout":
    case "mfa_attempts_exceeded":
    case "mfa_exhausted":
    case "mfa_not_configured":
    case "physical_mfa_unsupported":
    case "unsupported_mfa_method":
      return "ApplicantEncounteredArgyleMfaError"

    // Platform Errors - Payroll system unavailable
    case "connection_unavailable":
    case "platform_temporarily_unavailable":
    case "platform_unavailable":
    case "service_unavailable":
    case "auth_method_temporarily_unavailable":
    case "ongoing_refresh_disabled":
      return "ApplicantEncounteredArgylePlatformError"

    // Account Errors - Account state/configuration issues
    case "account_disabled":
    case "account_inaccessible":
    case "account_incomplete":
    case "account_nonunique":
    case "account_not_found":
    case "duplicate_account":
    case "existing_account_found":
    case "multi_driver_account":
    case "insufficient_account_data":
      return "ApplicantEncounteredArgyleAccountStateError"

    // Credential Errors - Employer/provider selection issues
    case "invalid_account_type":
    case "invalid_employer_identifier":
    case "invalid_login_method":
    case "invalid_login_url":
    case "invalid_store_identifier":
    case "unrecognized_employer_email":
    case "unsupported_business_account":
    case "credentials_managed_by_organization":
      return "ApplicantEncounteredArgyleCredentialError"

    // Credential Errors - Employer/provider selection issues
    case "unsupported_language":
      return "ApplicantEncounteredArgyleLanguageError"

    // Limit Errors - Rate limits and user-triggered issues
    case "all_employers_connected":
    case "login_attempts_exceeded":
    case "session_limit_reached":
    case "trial_connections_exhausted":
    case "trial_period_expired":
    case "user_action_timeout":
      return "ApplicantEncounteredArgyleLimitError"

    // System Error - Argyle Encountered an unexpected system error.
    case "system_error":
      return "ApplicantEncounteredArgyleSystemError"

    // Default to system error for unknown codes
    default:
      return "ApplicantEncounteredArgyleUnknownError"
  }
}
