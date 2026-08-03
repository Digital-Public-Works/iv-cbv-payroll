#---------------
# Load balancer
#---------------

# ALB for an app running in ECS
#trivy:ignore:aws-0053 Public web application; internet-facing ALB is intentional
resource "aws_lb" "alb" {
  depends_on      = [aws_s3_bucket_policy.access_logs]
  name            = var.service_name
  idle_timeout    = "120"
  internal        = false
  security_groups = [aws_security_group.alb.id]
  subnets         = var.public_subnet_ids

  # Use a separate line to support automated terraform destroy commands
  # checkov:skip=CKV_AWS_150:Allow deletion for automated tests
  enable_deletion_protection = !var.is_temporary

  # checkov:skip=CKV2_AWS_20:Redirect HTTP to HTTPS as part of implementing HTTPS support; tracked in PF-800

  # checkov:skip=CKV2_AWS_28:No WAF in front of the app ALB (unlike CloudFront/static-assets, which are intentionally
  # unprotected as low-value targets). This one fronts the actual application and has no real tracking ticket today
  # see PF-796 to evaluate adding a WAF here.

  # Drop invalid HTTP headers for improved security
  # Note that header names cannot contain underscores
  # https://docs.bridgecrew.io/docs/ensure-that-alb-drops-http-headers
  drop_invalid_header_fields = true

  access_logs {
    bucket  = aws_s3_bucket.access_logs.id
    prefix  = "${var.service_name}-lb"
    enabled = true
  }
}

# TODO PF-800: redirect HTTP->HTTPS at the ALB. HTTP->HTTPS enforced by Rails config.force_ssl
# See `navapbc/template-infra`'s fix: https://github.com/navapbc/template-infra/commit/f9785a860360d849e6733a26f358f50dfd4d6a80
#trivy:ignore:aws-0054
resource "aws_lb_listener" "alb_listener_http" {
  # checkov:skip=CKV_AWS_2:HTTP->HTTPS enforced by Rails config.force_ssl; see PF-800
  # checkov:skip=CKV_AWS_103:Require TLS 1.2 as part of implementing HTTPS support; tracked in PF-800

  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "app_http_forward" {
  listener_arn = aws_lb_listener.alb_listener_http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

resource "aws_lb_listener" "alb_listener_https" {
  count = var.certificate_arn != null ? 1 : 0

  load_balancer_arn = aws_lb.alb.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn

  # Use security policy that supports TLS 1.3 but requires at least TLS 1.2
  ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "app_https_forward" {
  count = var.certificate_arn != null ? 1 : 0

  listener_arn = aws_lb_listener.alb_listener_https[0].arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

resource "aws_lb_target_group" "app_tg" {
  # checkov:skip=CKV_AWS_378:TLS terminates at the ALB; HTTP between ALB and container is within the VPC
  # you must use a prefix, to facilitate successful tg changes
  name_prefix          = "app-"
  port                 = var.container_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = "30"

  health_check {
    path                = "/health"
    port                = var.container_port
    healthy_threshold   = 2
    unhealthy_threshold = 10
    interval            = 30
    timeout             = 29
    matcher             = "200-299"
  }

  lifecycle {
    create_before_destroy = true
  }
}
