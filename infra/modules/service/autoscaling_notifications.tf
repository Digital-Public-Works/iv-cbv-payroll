#---------------------------------------------------------------------------
# Autoscaling notifications to New Relic
#
# Sends a `VMIAutoscaling` custom event to New Relic whenever web or worker
# autoscaling scales out (action scale_up), scales in (scale_down), reaches
# its maximum (max_reached), or has stayed at its maximum for
# autoscaling_at_max_alert_minutes (at_max_sustained, a sign the maximum may
# be too low).
#
#
# Example NRQL:
#   SELECT * FROM VMIAutoscaling SINCE 1 week ago
#   SELECT count(*) FROM VMIAutoscaling WHERE action = 'max_reached' FACET service
#---------------------------------------------------------------------------

locals {
  autoscaling_notifications_enabled = var.enable_autoscaling_notifications

  # One entry per task count above the floor, up to and including the maximum.
  autoscaling_notification_levels = merge(
    local.autoscaling_notifications_enabled && local.web_autoscaling_enabled ? {
      for count in range(var.desired_instance_count + 1, local.web_max_instance_count + 1) :
      "web-${count}" => {
        role         = "web"
        ecs_service  = aws_ecs_service.app.name
        task_count   = count
        min_capacity = local.web_min_instance_count
        max_capacity = local.web_max_instance_count
      }
    } : {},
    local.autoscaling_notifications_enabled && local.worker_autoscaling_enabled ? {
      for count in range(var.shoryuken_desired_instance_count + 1, local.worker_max_instance_count + 1) :
      "worker-${count}" => {
        role         = "worker"
        ecs_service  = aws_ecs_service.worker[0].name
        task_count   = count
        min_capacity = local.worker_min_instance_count
        max_capacity = local.worker_max_instance_count
      }
    } : {},
  )

  # Each level sends one event when crossed upwards and one when crossed
  # downwards.
  autoscaling_notification_rules = merge([
    for key, level in local.autoscaling_notification_levels : {
      "${key}-up" = merge(level, {
        level_key  = key
        state      = "ALARM"
        action     = level.task_count == level.max_capacity ? "max_reached" : "scale_up"
        task_count = level.task_count
      })
      "${key}-down" = merge(level, {
        level_key  = key
        state      = "OK"
        action     = "scale_down"
        task_count = level.task_count - 1
      })
    }
  ]...)

  autoscaling_at_max_alert_minutes = 30

  # The levels that are each service's maximum.
  autoscaling_max_levels = {
    for key, level in local.autoscaling_notification_levels : level.role => level
    if level.task_count == level.max_capacity
  }
}

resource "aws_cloudwatch_metric_alarm" "autoscaling_task_count" {
  for_each = local.autoscaling_notification_levels

  alarm_name        = "${var.service_name}-${each.value.role}-tasks-at-least-${each.value.task_count}"
  alarm_description = "${each.value.ecs_service} autoscaled to ${each.value.task_count} or more tasks (floor ${each.value.min_capacity}, maximum ${each.value.max_capacity}). Notification only; scaling is driven by the target-tracking policies."

  namespace           = "ECS/ContainerInsights"
  metric_name         = "DesiredTaskCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = each.value.task_count
  # Gaps in Container Insights data shouldn't look like scaling.
  treat_missing_data = "ignore"

  dimensions = {
    ClusterName = aws_ecs_cluster.cluster.name
    ServiceName = each.value.ecs_service
  }
}

resource "aws_cloudwatch_event_rule" "autoscaling_notification" {
  for_each = local.autoscaling_notification_rules

  name        = "${var.service_name}-autoscaling-${each.key}"
  description = "Send a VMIAutoscaling ${each.value.action} event to New Relic for ${each.value.ecs_service}"

  event_pattern = jsonencode({
    source        = ["aws.cloudwatch"]
    "detail-type" = ["CloudWatch Alarm State Change"]
    resources     = [aws_cloudwatch_metric_alarm.autoscaling_task_count[each.value.level_key].arn]
    detail = merge(
      { state = { value = [each.value.state] } },
      # Only a real scale-in: ignore the alarm's first evaluation (from
      # INSUFFICIENT_DATA to OK) when it is created.
      each.value.state == "OK" ? { previousState = { value = ["ALARM"] } } : {},
    )
  })
}

resource "aws_cloudwatch_event_target" "autoscaling_notification" {
  for_each = local.autoscaling_notification_rules

  rule     = aws_cloudwatch_event_rule.autoscaling_notification[each.key].name
  arn      = var.newrelic_api_destination_arn
  role_arn = aws_iam_role.autoscaling_notifications[0].arn

  input_transformer {
    input_paths = {
      time  = "$.time"
      alarm = "$.detail.alarmName"
    }

    input_template = <<-EOF
      {
        "eventType": "VMIAutoscaling",
        "service": "${each.value.ecs_service}",
        "role": "${each.value.role}",
        "action": "${each.value.action}",
        "taskCount": ${each.value.task_count},
        "minCapacity": ${each.value.min_capacity},
        "maxCapacity": ${each.value.max_capacity},
        "alarmName": "<alarm>",
        "awsTime": "<time>"
      }
    EOF
  }
}

resource "aws_iam_role" "autoscaling_notifications" {
  count = length(local.autoscaling_notification_rules) > 0 ? 1 : 0

  name = "${var.service_name}-autoscaling-notifications"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "autoscaling_notifications" {
  count = length(local.autoscaling_notification_rules) > 0 ? 1 : 0

  name = "${var.service_name}-autoscaling-notifications"
  role = aws_iam_role.autoscaling_notifications[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["events:InvokeApiDestination"]
      Resource = [var.newrelic_api_destination_arn]
    }]
  })
}

#---------------------------------------------------------------------------
# Sustained at maximum
#
# ALARM when the desired count has been at the maximum for every minute of
# the last autoscaling_at_max_alert_minutes: autoscaling wants more tasks than
# it is allowed, or load stayed high enough to keep it there.
#---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "autoscaling_at_max" {
  for_each = local.autoscaling_max_levels

  alarm_name        = "${var.service_name}-${each.key}-at-max-${local.autoscaling_at_max_alert_minutes}m"
  alarm_description = "${each.value.ecs_service} has run its maximum of ${each.value.max_capacity} tasks for ${local.autoscaling_at_max_alert_minutes} minutes. Consider raising the maximum. Notification only."

  namespace           = "ECS/ContainerInsights"
  metric_name         = "DesiredTaskCount"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = local.autoscaling_at_max_alert_minutes
  datapoints_to_alarm = local.autoscaling_at_max_alert_minutes
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = each.value.max_capacity
  treat_missing_data  = "ignore"

  dimensions = {
    ClusterName = aws_ecs_cluster.cluster.name
    ServiceName = each.value.ecs_service
  }
}

resource "aws_cloudwatch_event_rule" "autoscaling_at_max" {
  for_each = local.autoscaling_max_levels

  name        = "${var.service_name}-autoscaling-${each.key}-at-max"
  description = "Send a VMIAutoscaling at_max_sustained event to New Relic for ${each.value.ecs_service}"

  event_pattern = jsonencode({
    source        = ["aws.cloudwatch"]
    "detail-type" = ["CloudWatch Alarm State Change"]
    resources     = [aws_cloudwatch_metric_alarm.autoscaling_at_max[each.key].arn]
    detail        = { state = { value = ["ALARM"] } }
  })
}

resource "aws_cloudwatch_event_target" "autoscaling_at_max" {
  for_each = local.autoscaling_max_levels

  rule     = aws_cloudwatch_event_rule.autoscaling_at_max[each.key].name
  arn      = var.newrelic_api_destination_arn
  role_arn = aws_iam_role.autoscaling_notifications[0].arn

  input_transformer {
    input_paths = {
      time  = "$.time"
      alarm = "$.detail.alarmName"
    }

    input_template = <<-EOF
      {
        "eventType": "VMIAutoscaling",
        "service": "${each.value.ecs_service}",
        "role": "${each.value.role}",
        "action": "at_max_sustained",
        "taskCount": ${each.value.max_capacity},
        "minCapacity": ${each.value.min_capacity},
        "maxCapacity": ${each.value.max_capacity},
        "minutesAtMax": ${local.autoscaling_at_max_alert_minutes},
        "alarmName": "<alarm>",
        "awsTime": "<time>"
      }
    EOF
  }
}
