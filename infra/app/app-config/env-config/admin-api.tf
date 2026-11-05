locals {
  # The admin API exists only while ADMIN_API_SERVICE_SECRET is set (see the
  # app's routes.rb). The SSM parameter must exist before the first deploy with
  # admin_api set, or the tasks won't start.
  admin_api_secrets = var.admin_api == null ? {} : {
    ADMIN_API_SERVICE_SECRET = {
      manage_method     = "manual"
      secret_store_name = "/service/${var.app_name}-${var.environment}/admin-api-service-secret"
    }
  }

  admin_api_environment_variables = var.admin_api == null ? {} : {
    ADMIN_API_SETTINGS_WRITABLE = var.admin_api.settings_writable ? "true" : "false"
  }
}
