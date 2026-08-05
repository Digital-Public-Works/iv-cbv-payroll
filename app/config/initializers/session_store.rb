# Skip session expiry in E2E runs
# TODO: if we ever want e2e coverage of expiry behavior, we should revisit
if ENV["E2E_RUN_TESTS"].nil?
  Rails.application.config.session_store :cookie_store,
    key: "_iv_cbv_payroll_session",
    expire_after: Rails.application.config.cbv_session_expires_after
end
