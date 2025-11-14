type LinkError = {
  userId: string
  errorType: string
  errorMessage: string
  errorDetails: string
}

type ArgyleInitializationParams = {
  // See: https://docs.argyle.com/link/initialization
  flowId: string
  userToken: string
  items: string[]
  onAccountConnected?: (payload: ArgyleAccountData) => void
  onTokenExpired?: (updateToken: Function) => void
  onAccountCreated?: (payload: ArgyleAccountData) => void
  onAccountError?: (payload: ArgyleAccountData) => void
  onAccountRemoved?: (payload: ArgyleAccountData) => void
  onClose?: () => void
  onError?: (payload: LinkError) => void
  onUIEvent?: (payload: ArgyleUIEvent) => void
  sandbox?: boolean
}

type Argyle = {
  create: (params: ArgyleInitializationParams) => {
    open: () => void
    close: () => void
  }
}

type ArgyleAccountData = {
  accountId: string
  userId: string
  itemId: string
}

type ArgyleUIEvent = {
  name: string
  properties: {
    deepLink: boolean
    userId: string
    accountId?: string
    itemId?: string
    errorCode?: // Authentication Errors (7)
    | "auth_required"
      | "invalid_auth"
      | "invalid_credentials"
      | "expired_credentials"
      | "full_auth_required"
      | "tos_required"
      | "unsupported_auth_type"
      // MFA Errors (8)
      | "invalid_mfa"
      | "mfa_cancelled_by_the_user"
      | "mfa_timeout"
      | "mfa_attempts_exceeded"
      | "mfa_exhausted"
      | "mfa_not_configured"
      | "physical_mfa_unsupported"
      | "unsupported_mfa_method"
      // Platform Errors (5)
      | "connection_unavailable"
      | "platform_temporarily_unavailable"
      | "platform_unavailable"
      | "service_unavailable"
      | "auth_method_temporarily_unavailable"
      // Account Errors (9)
      | "account_disabled"
      | "account_inaccessible"
      | "account_incomplete"
      | "account_nonunique"
      | "account_not_found"
      | "duplicate_account"
      | "existing_account_found"
      | "multi_driver_account"
      | "insufficient_account_data"
      // Credential Errors (8)
      | "invalid_account_type"
      | "invalid_employer_identifier"
      | "invalid_login_method"
      | "invalid_login_url"
      | "invalid_store_identifier"
      | "unrecognized_employer_email"
      | "unsupported_business_account"
      | "credentials_managed_by_organization"
      // Limit Errors (6)
      | "all_employers_connected"
      | "login_attempts_exceeded"
      | "session_limit_reached"
      | "trial_connections_exhausted"
      | "trial_period_expired"
      | "user_action_timeout"
      // System Errors (12)
      | "system_error"
      | "ongoing_refresh_disabled"
      | "unsupported_language"
      | "generic"
      | "invalid_user_token"
      | "expired_user_token"
      | "invalid_items"
      | "invalid_account_id"
      | "invalid_dds_config"
      | "incompatible_dds_config"
      | "callback_undefined"
      | "dds_not_supported"
    errorMessage?: string
    term?: string
    tab?: string
  }
}
