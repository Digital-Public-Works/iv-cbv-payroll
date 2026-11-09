# Private API gateway for the partner-config admin API, used by the vmi-admin
# portal. Only for environments whose app-config sets admin_api, and never for
# temporary (PR) environments: they share demo's config, and the invoker role
# name is fixed.

locals {
  admin_api_config  = local.environment_config.admin_api_config
  admin_api_enabled = local.admin_api_config != null && !local.is_temporary
}

data "aws_ssm_parameter" "admin_api_invoker_external_id" {
  count = local.admin_api_enabled && try(local.admin_api_config.invoker_external_id_param, null) != null ? 1 : 0
  name  = local.admin_api_config.invoker_external_id_param
}

module "admin_api_gateway" {
  count  = local.admin_api_enabled ? 1 : 0
  source = "../../modules/admin-api-gateway"

  name               = local.service_config.service_name
  vpc_id             = data.aws_vpc.network.id
  vpc_cidr           = data.aws_vpc.network.cidr_block
  private_subnet_ids = data.aws_subnets.private.ids
  domain_name        = local.service_config.domain_name

  load_balancer_arn    = module.service.load_balancer_arn
  https_listener_arn   = module.service.https_listener_arn
  app_target_group_arn = module.service.app_target_group_arn

  portal_task_role_arn   = local.admin_api_config.portal_task_role_arn
  source_vpc_endpoint_id = local.admin_api_config.source_vpc_endpoint_id
  invoker_external_id    = length(data.aws_ssm_parameter.admin_api_invoker_external_id) > 0 ? data.aws_ssm_parameter.admin_api_invoker_external_id[0].value : null

  is_temporary = local.is_temporary
}

output "admin_api_invoke_url" {
  description = "The portal's VMI_DEMO_URL / VMI_PROD_URL (demo_admin_api_url / prod_admin_api_url in vmi-admin/infra/service)"
  value       = local.admin_api_enabled ? module.admin_api_gateway[0].invoke_url : null
}

output "admin_api_stage_execution_arn" {
  description = "prod_admin_api_arn in vmi-admin/infra/identity (prod only)"
  value       = local.admin_api_enabled ? module.admin_api_gateway[0].stage_execution_arn : null
}

output "admin_api_vpc_endpoint_id" {
  description = "Prod's value is demo's admin_api.source_vpc_endpoint_id"
  value       = local.admin_api_enabled ? module.admin_api_gateway[0].vpc_endpoint_id : null
}

output "admin_api_invoker_role_arn" {
  value = local.admin_api_enabled ? module.admin_api_gateway[0].invoker_role_arn : null
}
