output "invoke_url" {
  description = "Base URL for the portal (VMI_DEMO_URL / VMI_PROD_URL): the endpoint-specific hostname plus the stage"
  value       = "https://${aws_api_gateway_rest_api.admin_api.id}-${local.vpc_endpoint_id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${local.stage_name}"
}

output "stage_execution_arn" {
  description = "For the portal's execute-api:Invoke grant (prod_admin_api_arn in vmi-admin/infra/identity)"
  value       = "${aws_api_gateway_rest_api.admin_api.execution_arn}/${local.stage_name}"
}

output "vpc_endpoint_id" {
  description = "The execute-api endpoint the API accepts calls through; demo's source_vpc_endpoint_id is prod's value"
  value       = local.vpc_endpoint_id
}

output "invoker_role_arn" {
  value = local.create_invoker_role ? aws_iam_role.invoker[0].arn : null
}
