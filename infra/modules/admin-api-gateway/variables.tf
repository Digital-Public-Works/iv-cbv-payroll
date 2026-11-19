variable "name" {
  type        = string
  description = "Prefix for resource names (the service name, e.g. app-prod)"
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type        = string
  description = "The VPC's CIDR block: allowed to the execute-api endpoint, and the only source the ALB lets through to /api/admin"
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "domain_name" {
  type        = string
  description = "The service's domain: sent as Host and checked against the ALB's certificate"
}

variable "load_balancer_arn" {
  type        = string
  description = "The service's ALB, registered as the NLB's target"
}

variable "https_listener_arn" {
  type        = string
  description = "The ALB's HTTPS listener, where the private admin-path rule is added"
}

variable "app_target_group_arn" {
  type        = string
  description = "The ALB target group the private admin-path rule forwards to"
}

variable "portal_task_role_arn" {
  type        = string
  description = "The vmi-admin portal's ECS task role (prod account). It must exist before this is applied when an invoker role is created."
}

variable "source_vpc_endpoint_id" {
  type        = string
  description = "The portal VPC's execute-api endpoint. Null creates it in this VPC (prod); set it to prod's endpoint id for demo."
  default     = null
}

variable "invoker_external_id" {
  type        = string
  description = "Set for a cross-account environment (demo): creates the invoker role the portal assumes, requiring this ExternalId"
  default     = null
  sensitive   = true
}

variable "invoker_role_name" {
  type    = string
  default = "vmi-admin-demo-invoker"
}

variable "is_temporary" {
  type    = bool
  default = false
}
