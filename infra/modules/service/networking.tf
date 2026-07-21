#-----------------------
# Network Configuration
#-----------------------

resource "aws_security_group" "alb" {
  # Specify name_prefix instead of name because when a change requires creating a new
  # security group, sometimes the change requires the new security group to be created
  # before the old one is destroyed. In this situation, the new one needs a unique name
  name_prefix = "${var.service_name}-alb"
  description = "Allow TCP traffic to application load balancer"

  lifecycle {
    create_before_destroy = true

    # changing the description is a destructive change
    # just ignore it
    ignore_changes = [description]
  }

  vpc_id = var.vpc_id

  # checkov:skip=CKV_AWS_260:Port 80 forwards to the app, but HTTP->HTTPS is enforced by Rails config.force_ssl (verified live).
  # TODO: redirect at the ALB too (defense in depth) per navapbc/template-infra's fix:
  # https://github.com/navapbc/template-infra/commit/f9785a860360d849e6733a26f358f50dfd4d6a80
  ingress {
    description = "Allow HTTP traffic from public internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS traffic from public internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # checkov:skip=CKV_AWS_382:Open egress needed to reach external services (e.g. Argyle); see PF-XXX to scope egress rules
  # trivy:ignore:aws-0104 Open egress needed to reach external services (e.g. Argyle); see PF-XXX to scope egress rules
  egress {
    description = "Allow all outgoing traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security group to allow access to Fargate tasks
resource "aws_security_group" "app" {
  # Specify name_prefix instead of name because when a change requires creating a new
  # security group, sometimes the change requires the new security group to be created
  # before the old one is destroyed. In this situation, the new one needs a unique name
  name_prefix = "${var.service_name}-app"
  description = "Allow inbound TCP access to application container port"
  vpc_id      = var.vpc_id
  lifecycle {
    create_before_destroy = true
  }
}

#trivy:ignore:aws-0104 Open egress needed to reach external services (e.g. Argyle); see PF-XXX to scope egress rules
resource "aws_vpc_security_group_egress_rule" "service_egress_to_all" {
  security_group_id = aws_security_group.app.id
  description       = "Allow all outgoing traffic from application"

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "service_ingress_from_load_balancer" {
  security_group_id = aws_security_group.app.id
  description       = "Allow HTTP traffic to application container port"

  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_ingress_from_service" {
  security_group_id = var.aws_services_security_group_id
  description       = "Allow inbound requests to VPC endpoints from role manager"

  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.app.id
}
