#---------------------------------------------------------------------------
# Service autoscaling
#
# All services have a floor with scale out triggers. 'desired_count' (initial count)
# is ignored after creation so we don't shut down running instances of on future deploy
#---------------------------------------------------------------------------

locals {
  web_max_instance_count    = coalesce(var.max_instance_count, var.desired_instance_count)
  worker_max_instance_count = coalesce(var.shoryuken_max_instance_count, var.shoryuken_desired_instance_count)

  web_autoscaling_enabled    = local.web_max_instance_count > var.desired_instance_count
  worker_autoscaling_enabled = !var.is_temporary && local.worker_max_instance_count > var.shoryuken_desired_instance_count

  # Published by the web tasks only while web autoscaling is on.
  puma_metrics_namespace = "VMI/Puma"

  autoscaling_cpu_target         = 60
  autoscaling_puma_thread_target = 70
  autoscaling_scale_out_cooldown = 60
  autoscaling_scale_in_cooldown  = 300
}

#---------------------------------------------------------------------------
# Web
#---------------------------------------------------------------------------

resource "aws_appautoscaling_target" "web" {
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.app.name}"
  min_capacity       = var.desired_instance_count
  max_capacity       = local.web_max_instance_count

  lifecycle {
    precondition {
      condition     = local.web_max_instance_count >= var.desired_instance_count
      error_message = "max_instance_count must be at least desired_instance_count."
    }
  }
}

resource "aws_appautoscaling_policy" "web_cpu" {
  count = local.web_autoscaling_enabled ? 1 : 0

  name               = "${var.service_name}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.web.service_namespace
  resource_id        = aws_appautoscaling_target.web.resource_id
  scalable_dimension = aws_appautoscaling_target.web.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = local.autoscaling_cpu_target
    scale_out_cooldown = local.autoscaling_scale_out_cooldown
    scale_in_cooldown  = local.autoscaling_scale_in_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "web_puma_threads" {
  count = local.web_autoscaling_enabled ? 1 : 0

  name               = "${var.service_name}-puma-threads"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.web.service_namespace
  resource_id        = aws_appautoscaling_target.web.resource_id
  scalable_dimension = aws_appautoscaling_target.web.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = local.autoscaling_puma_thread_target
    scale_out_cooldown = local.autoscaling_scale_out_cooldown
    scale_in_cooldown  = local.autoscaling_scale_in_cooldown

    # Busy threads plus queued requests as a percentage of max threads,
    # averaged across tasks. Over 100 means requests are waiting for a thread.
    customized_metric_specification {
      namespace   = local.puma_metrics_namespace
      metric_name = "ThreadUtilization"
      statistic   = "Average"
      unit        = "Percent"

      dimensions {
        name  = "ServiceName"
        value = var.service_name
      }
    }
  }
}

# The web tasks publish the Puma metric themselves. PutMetricData has no
# resource-level permissions, so it's limited to the namespace by condition.
data "aws_iam_policy_document" "puma_metrics" {
  statement {
    sid       = "PublishPumaMetrics"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = [local.puma_metrics_namespace]
    }
  }
}

resource "aws_iam_role_policy" "puma_metrics" {
  # checkov:skip=CKV_AWS_355:PutMetricData has no resource-level permissions; the namespace condition scopes it
  count = local.web_autoscaling_enabled ? 1 : 0

  name   = "${var.service_name}-puma-metrics"
  role   = aws_iam_role.app_service.id
  policy = data.aws_iam_policy_document.puma_metrics.json
}

#---------------------------------------------------------------------------
# Worker
#---------------------------------------------------------------------------

resource "aws_appautoscaling_target" "worker" {
  count = var.is_temporary ? 0 : 1

  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.worker[0].name}"
  min_capacity       = var.shoryuken_desired_instance_count
  max_capacity       = local.worker_max_instance_count

  lifecycle {
    precondition {
      condition     = local.worker_max_instance_count >= var.shoryuken_desired_instance_count
      error_message = "shoryuken_max_instance_count must be at least shoryuken_desired_instance_count."
    }
  }
}

resource "aws_appautoscaling_policy" "worker_cpu" {
  count = local.worker_autoscaling_enabled ? 1 : 0

  name               = "${var.service_name}-worker-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.worker[0].service_namespace
  resource_id        = aws_appautoscaling_target.worker[0].resource_id
  scalable_dimension = aws_appautoscaling_target.worker[0].scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = local.autoscaling_cpu_target
    scale_out_cooldown = local.autoscaling_scale_out_cooldown
    scale_in_cooldown  = local.autoscaling_scale_in_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

# scaling for report sender
resource "aws_appautoscaling_policy" "worker_backlog" {
  count = local.worker_autoscaling_enabled && var.worker_backlog_queue_name != null ? 1 : 0

  name               = "${var.service_name}-worker-backlog"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.worker[0].service_namespace
  resource_id        = aws_appautoscaling_target.worker[0].resource_id
  scalable_dimension = aws_appautoscaling_target.worker[0].scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.worker_backlog_per_task_target
    scale_out_cooldown = local.autoscaling_scale_out_cooldown
    scale_in_cooldown  = local.autoscaling_scale_in_cooldown

    # Messages waiting for a worker thread, per running worker task. Delayed
    # messages (ActiveJob retries) aren't visible yet, so they don't count.
    customized_metric_specification {
      metrics {
        id          = "visible"
        return_data = false

        metric_stat {
          stat = "Average"

          metric {
            namespace   = "AWS/SQS"
            metric_name = "ApproximateNumberOfMessagesVisible"

            dimensions {
              name  = "QueueName"
              value = var.worker_backlog_queue_name
            }
          }
        }
      }

      # Needs Container Insights, which the cluster enables.
      metrics {
        id          = "tasks"
        return_data = false

        metric_stat {
          stat = "Average"

          metric {
            namespace   = "ECS/ContainerInsights"
            metric_name = "RunningTaskCount"

            dimensions {
              name  = "ClusterName"
              value = aws_ecs_cluster.cluster.name
            }
            dimensions {
              name  = "ServiceName"
              value = aws_ecs_service.worker[0].name
            }
          }
        }
      }

      metrics {
        id          = "backlog_per_task"
        label       = "report_sender messages visible per running worker task"
        expression  = "visible / tasks"
        return_data = true
      }
    }
  }
}

# scaling for mixpanel and newrelic events
resource "aws_appautoscaling_policy" "worker_event_backlog" {
  count = local.worker_autoscaling_enabled && length(var.worker_event_queue_names) > 0 ? 1 : 0

  name               = "${var.service_name}-worker-event-backlog"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.worker[0].service_namespace
  resource_id        = aws_appautoscaling_target.worker[0].resource_id
  scalable_dimension = aws_appautoscaling_target.worker[0].scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.worker_event_backlog_per_task_target
    scale_out_cooldown = local.autoscaling_scale_out_cooldown
    scale_in_cooldown  = local.autoscaling_scale_in_cooldown

    customized_metric_specification {
      dynamic "metrics" {
        for_each = var.worker_event_queue_names

        content {
          id          = "events${metrics.key}"
          return_data = false

          metric_stat {
            stat = "Average"

            metric {
              namespace   = "AWS/SQS"
              metric_name = "ApproximateNumberOfMessagesVisible"

              dimensions {
                name  = "QueueName"
                value = metrics.value
              }
            }
          }
        }
      }

      metrics {
        id          = "tasks"
        return_data = false

        metric_stat {
          stat = "Average"

          metric {
            namespace   = "ECS/ContainerInsights"
            metric_name = "RunningTaskCount"

            dimensions {
              name  = "ClusterName"
              value = aws_ecs_cluster.cluster.name
            }
            dimensions {
              name  = "ServiceName"
              value = aws_ecs_service.worker[0].name
            }
          }
        }
      }

      metrics {
        id          = "event_backlog_per_task"
        label       = "Analytics event messages visible per running worker task"
        expression  = "(${join(" + ", [for i in range(length(var.worker_event_queue_names)) : "events${i}"])}) / tasks"
        return_data = true
      }
    }
  }
}
