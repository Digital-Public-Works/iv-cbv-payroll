#---------------------------------------------------------------------------
# Private admin API gateway
#
# The vmi-admin portal (prod account) reaches this environment's admin API
# (/api/admin/v1) only through here:
#
#   portal task --SigV4--> execute-api VPC endpoint (prod VPC)
#     --> private REST API (IAM auth, resource policy pinned to that endpoint)
#     --> VPC link --> internal NLB --TLS passthrough--> this service's ALB :443
#     --> priority-5 rule (admin path AND source in this VPC) --> app
#
# Going through the ALB's HTTPS listener means the app sees the request exactly
# as it sees public traffic: X-Forwarded-Proto=https (force_ssl), Host = the
# service domain (config.hosts). From the internet, /api/admin still gets the
# priority-10 fixed 404 (modules/service/load-balancer.tf): the allow rule
# matches only private source addresses, which internet clients can't use.
#
# The admin API also checks its own HMAC signature on every request; this
# gateway is the network layer, not the only one.
#---------------------------------------------------------------------------

data "aws_region" "current" {}

locals {
  create_vpc_endpoint = var.source_vpc_endpoint_id == null
  vpc_endpoint_id     = local.create_vpc_endpoint ? aws_vpc_endpoint.execute_api[0].id : var.source_vpc_endpoint_id
  # Whether an ExternalId is set isn't secret; its value is.
  create_invoker_role = nonsensitive(var.invoker_external_id != null)

  # Cross-account (demo): the portal assumes the invoker role, which calls the
  # API. Same account (prod): the portal's task role calls it directly.
  caller_arns = local.create_invoker_role ? [aws_iam_role.invoker[0].arn] : [var.portal_task_role_arn]

  stage_name = "admin"
}

#---------------------------------------------------------------------------
# execute-api VPC endpoint (only in the portal's VPC, i.e. prod)
#
# Private DNS stays off so the VPC can still call public API Gateway APIs
# (partner webhooks may be hosted on execute-api). Callers use the
# endpoint-specific hostname from the invoke_url output instead.
#
# One AZ only: the endpoint is billed per AZ, and the portal is an internal
# tool that can wait out an AZ outage. Tasks in other AZs still reach it.
# Sorted so the choice doesn't change (and replace the endpoint) between plans.
#---------------------------------------------------------------------------

resource "aws_security_group" "execute_api_endpoint" {
  count = local.create_vpc_endpoint ? 1 : 0

  name_prefix = "${var.name}-execute-api-"
  description = "HTTPS from inside the VPC to the execute-api endpoint (vmi-admin portal)"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from the VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_endpoint" "execute_api" {
  count = local.create_vpc_endpoint ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.execute-api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = slice(sort(var.private_subnet_ids), 0, 1)
  security_group_ids  = [aws_security_group.execute_api_endpoint[0].id]
  private_dns_enabled = false
}

#---------------------------------------------------------------------------
# Internal NLB in front of the ALB (REST API VPC links target NLBs)
#---------------------------------------------------------------------------

resource "aws_lb" "admin_api" {
  # checkov:skip=CKV_AWS_91:Requests are logged by the app's admin API action log; NLB flow logs add nothing here
  name                             = substr("${var.name}-admin-api", 0, 32)
  internal                         = true
  load_balancer_type               = "network"
  subnets                          = var.private_subnet_ids
  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = !var.is_temporary
}

resource "aws_lb_target_group" "alb" {
  name_prefix = "admapi"
  port        = 443
  protocol    = "TCP"
  target_type = "alb"
  vpc_id      = var.vpc_id

  health_check {
    protocol = "HTTPS"
    path     = "/health"
    port     = "traffic-port"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group_attachment" "alb" {
  target_group_arn = aws_lb_target_group.alb.arn
  target_id        = var.load_balancer_arn
  port             = 443
}

resource "aws_lb_listener" "admin_api" {
  load_balancer_arn = aws_lb.admin_api.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb.arn
  }
}

# Lets the admin path through the ALB for traffic that arrived over the NLB
# (source = the NLB's private addresses). Runs before the priority-10 block.
resource "aws_lb_listener_rule" "admin_api_private" {
  listener_arn = var.https_listener_arn
  priority     = 5

  action {
    type             = "forward"
    target_group_arn = var.app_target_group_arn
  }
  condition {
    path_pattern {
      values = ["/api/admin/*"]
    }
  }
  condition {
    source_ip {
      values = [var.vpc_cidr]
    }
  }
}

#---------------------------------------------------------------------------
# Private REST API
#---------------------------------------------------------------------------

resource "aws_api_gateway_vpc_link" "admin_api" {
  name        = "${var.name}-admin-api"
  target_arns = [aws_lb.admin_api.arn]
}

resource "aws_api_gateway_rest_api" "admin_api" {
  # checkov:skip=CKV_AWS_237:Recreating the API changes its id and the portal's URL; it's replaced deliberately, not automatically
  name        = "${var.name}-admin-api"
  description = "Private, IAM-authenticated route to the VMI admin API (/api/admin/v1) for the vmi-admin portal"

  endpoint_configuration {
    types            = ["PRIVATE"]
    vpc_endpoint_ids = [local.vpc_endpoint_id]
  }
}

resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.admin_api.id
  parent_id   = aws_api_gateway_rest_api.admin_api.root_resource_id
  path_part   = "api"
}

resource "aws_api_gateway_resource" "admin" {
  rest_api_id = aws_api_gateway_rest_api.admin_api.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "admin"
}

resource "aws_api_gateway_resource" "v1" {
  rest_api_id = aws_api_gateway_rest_api.admin_api.id
  parent_id   = aws_api_gateway_resource.admin.id
  path_part   = "v1"
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.admin_api.id
  parent_id   = aws_api_gateway_resource.v1.id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  # checkov:skip=CKV2_AWS_53:The admin API validates every request body itself
  rest_api_id   = aws_api_gateway_rest_api.admin_api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "AWS_IAM"

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "proxy" {
  rest_api_id             = aws_api_gateway_rest_api.admin_api.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "ANY"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.admin_api.id
  # With a VPC link the connection goes to the NLB; this host is only the Host
  # header and the name the ALB's certificate is checked against.
  uri                  = "https://${var.domain_name}/api/admin/v1/{proxy}"
  timeout_milliseconds = 29000

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}

data "aws_iam_policy_document" "invoke" {
  statement {
    sid       = "PortalThroughItsEndpoint"
    effect    = "Allow"
    actions   = ["execute-api:Invoke"]
    resources = ["${aws_api_gateway_rest_api.admin_api.execution_arn}/*"]
    principals {
      type        = "AWS"
      identifiers = local.caller_arns
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceVpce"
      values   = [local.vpc_endpoint_id]
    }
  }

  statement {
    sid       = "DenyOtherEndpoints"
    effect    = "Deny"
    actions   = ["execute-api:Invoke"]
    resources = ["${aws_api_gateway_rest_api.admin_api.execution_arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceVpce"
      values   = [local.vpc_endpoint_id]
    }
  }
}

resource "aws_api_gateway_rest_api_policy" "admin_api" {
  rest_api_id = aws_api_gateway_rest_api.admin_api.id
  policy      = data.aws_iam_policy_document.invoke.json
}

resource "aws_api_gateway_deployment" "admin_api" {
  rest_api_id = aws_api_gateway_rest_api.admin_api.id

  # A private API serves only what was deployed, including its resource policy.
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.proxy.id,
      aws_api_gateway_method.proxy,
      aws_api_gateway_integration.proxy,
      aws_api_gateway_rest_api_policy.admin_api.policy,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_api_gateway_integration.proxy, aws_api_gateway_rest_api_policy.admin_api]
}

resource "aws_api_gateway_stage" "admin" {
  # checkov:skip=CKV_AWS_76:Access logging needs the account-level API Gateway CloudWatch role, which this project doesn't manage; the admin API logs every action itself
  # checkov:skip=CKV_AWS_73:X-Ray tracing isn't used in this project
  # checkov:skip=CKV_AWS_120:Admin requests must never be cached
  # checkov:skip=CKV2_AWS_51:Clients authenticate with SigV4 and the HMAC signature, not client certificates
  # checkov:skip=CKV2_AWS_29:Private API, reachable only through one VPC endpoint; WAF adds nothing
  # checkov:skip=CKV2_AWS_4:Execution logging needs the account-level API Gateway CloudWatch role
  rest_api_id   = aws_api_gateway_rest_api.admin_api.id
  deployment_id = aws_api_gateway_deployment.admin_api.id
  stage_name    = local.stage_name
}

#---------------------------------------------------------------------------
# Cross-account invoker role (demo): the portal's prod task role assumes it
#---------------------------------------------------------------------------

resource "aws_iam_role" "invoker" {
  count = local.create_invoker_role ? 1 : 0

  name                 = var.invoker_role_name
  description          = "Assumed by the vmi-admin portal (prod account) to call this environment's private admin API"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = var.portal_task_role_arn }
      Condition = { StringEquals = { "sts:ExternalId" = var.invoker_external_id } }
    }]
  })
}

resource "aws_iam_role_policy" "invoker" {
  count = local.create_invoker_role ? 1 : 0

  name = "invoke-admin-api"
  role = aws_iam_role.invoker[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "execute-api:Invoke"
      Resource = "${aws_api_gateway_rest_api.admin_api.execution_arn}/${local.stage_name}/*/api/admin/v1/*"
    }]
  })
}
