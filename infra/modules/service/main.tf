data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  alb_name                = var.service_name
  cluster_name            = var.service_name
  container_name          = var.service_name
  log_group_name          = "service/${var.service_name}"
  log_stream_prefix       = var.service_name
  task_executor_role_name = "${var.service_name}-task-executor"
  image_url               = "${var.image_repository_url}:${var.image_tag}"

  base_environment_variables = [
    { name : "DOMAIN_NAME", value : var.is_temporary ? aws_lb.alb.dns_name : tostring(var.domain_name) },
    { name : "PORT", value : tostring(var.container_port) },
    { name : "AWS_DEFAULT_REGION", value : data.aws_region.current.name },
    { name : "AWS_REGION", value : data.aws_region.current.name },
    { name : "IMAGE_TAG", value : var.image_tag },
  ]
  db_environment_variables = var.db_vars == null ? [] : [
    { name : "DB_HOST", value : var.db_vars.connection_info.host },
    { name : "DB_PORT", value : var.db_vars.connection_info.port },
    { name : "DB_USER", value : var.db_vars.connection_info.user },
    { name : "DB_NAME", value : var.db_vars.connection_info.db_name },
    { name : "DB_SCHEMA", value : var.db_vars.connection_info.schema_name },
  ]
  environment_variables = concat(
    local.base_environment_variables,
    local.db_environment_variables,
    [
      for name, value in var.extra_environment_variables :
      { name : name, value : value }
    ],
  )
}

#-------------------
# Service Execution
#-------------------

resource "aws_ecs_service" "app" {
  name                   = var.service_name
  cluster                = aws_ecs_cluster.cluster.arn
  launch_type            = "FARGATE"
  task_definition        = aws_ecs_task_definition.app.arn
  desired_count          = var.desired_instance_count
  enable_execute_command = var.enable_command_execution ? true : null

  # Deployment Circuit Breaker puts a limit on the number of retries that ECS will attempt
  # when launching a task before it gives up.  Without this, ECS could be in an infinite loop on a bad deploy
  # Circuit breaker attempts 3 times by default for a single deployment instance, otherwise it uses formula found at
  # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-circuit-breaker.html
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    assign_public_ip = false
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.app.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app_tg.arn
    container_name   = var.service_name
    container_port   = var.container_port
  }

  # Autoscaling owns the running count (autoscaling.tf); desired_count only
  # sets it when the service is first created.
  lifecycle {
    ignore_changes = [desired_count]
  }
}

resource "aws_ecs_task_definition" "app" {
  family             = var.service_name
  execution_role_arn = aws_iam_role.task_executor.arn
  task_role_arn      = aws_iam_role.app_service.arn

  container_definitions = jsonencode([
    {
      name        = local.container_name,
      image       = local.image_url,
      memory      = var.memory,
      cpu         = var.cpu,
      networkMode = "awsvpc",
      essential   = true,
      # TODO: Reenable readonlyRootFilesystem when we can have it behave
      # consistently in dev (demo) and production.
      # readonlyRootFilesystem = !var.enable_command_execution,
      readonlyRootFilesystem = false,

      # 120 second drain down to allow running processes (such as PDF generation) to finish before
      # the instance stops
      stopTimeout = 120,

      # Need to define all parameters in the healthCheck block even if we want
      # to use AWS's defaults, otherwise the terraform plan will show a diff
      # that will force a replacement of the task definition
      #
      # /health waits in Puma's request queue behind real traffic, and ECS
      # stops a task whose check fails `retries` times in a row. Lenient
      # enough that a task that is overloaded but still serving rides out a
      # traffic spike until autoscaling's new tasks arrive (about 5-7 minutes),
      # instead of being stopped; with one web task that would be an outage.
      # Takes about 2.5 minutes of failures (5 x 30s) to mark it unhealthy.
      healthCheck = {
        interval = 30,
        retries  = 5,
        timeout  = 15,
        command = ["CMD-SHELL",
          "curl --fail http://localhost:${var.container_port}/health"
        ]
      },

      environment = concat(
        local.environment_variables,
        local.web_autoscaling_enabled ? [{ name : "PUMA_METRICS_SERVICE_NAME", value : var.service_name }] : [],
        local.scale_to_zero ? [{ name : "ACTIVITY_METRICS_SERVICE_NAME", value : var.service_name }] : [],
      ),
      secrets = var.secrets,
      portMappings = [
        {
          containerPort = var.container_port,
          hostPort      = var.container_port,
          protocol      = "tcp"
        }
      ],
      linuxParameters = {
        capabilities = {
          add  = []
          drop = ["ALL"]
        },
        initProcessEnabled = true
      },
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.service_logs.name,
          "awslogs-region"        = data.aws_region.current.name,
          "awslogs-stream-prefix" = local.log_stream_prefix
        }
      },
      mountPoints = [
        {
          containerPath = "/rails/tmp",
          sourceVolume  = "${var.service_name}-tmp"
        }
      ]
    }
  ])

  cpu    = var.cpu
  memory = var.memory

  volume {
    name = "${var.service_name}-tmp"
  }

  requires_compatibilities = ["FARGATE"]

  # Reference https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-networking.html
  network_mode = "awsvpc"
}

resource "aws_ecs_cluster" "cluster" {
  name = local.cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}
