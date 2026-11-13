#---------------------------------------------------------------------------
# Scale to zero (var.scale_to_zero_idle_hours; used by a11y)
#
# Sleep: web and worker go to 0 tasks after scale_to_zero_idle_hours with no
#   CBV flows started and no invitations created. The app publishes that count
#   (VMI/Activity, see app/services/activity_cloud_watch_metrics.rb) every
#   minute, zeros included, while a web task runs.
# Wake: a WAF rule counts requests to the paths people use (/start...,
#   /cbv/..., POST /api/v1/invitations). Any such request sets web and worker
#   back to 1 task.
#
# The environment's background traffic is internet scanners (/, /RDWeb, /mcp,
# ...) and Argyle webhooks for users of other environments
# (/webhooks/argyle/events). It never creates flows or invitations and never
# requests the wake paths, so it can't keep the environment awake or wake it up.
#
# While asleep, the load balancer answers with 503. After a wake request the
# app is back in about 3-5 minutes (WAF metric delay, alarm, task start, health
# check).
#---------------------------------------------------------------------------

locals {
  wake_rule_metric_name = "${var.service_name}-wake-requests"

  # Alarms evaluate 5-minute periods, so the environment sleeps within 5
  # minutes of being idle for the full scale_to_zero_idle_hours.
  activity_alarm_period = 300
}

#---------------------------------------------------------------------------
# Sleep: no flows or invitations for scale_to_zero_idle_hours
#---------------------------------------------------------------------------

# The web tasks publish the activity metric themselves. PutMetricData has no
# resource-level permissions, so it's limited to the namespace by condition.
data "aws_iam_policy_document" "activity_metrics" {
  statement {
    sid       = "PublishActivityMetrics"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["VMI/Activity"]
    }
  }
}

resource "aws_iam_role_policy" "activity_metrics" {
  # checkov:skip=CKV_AWS_355:PutMetricData has no resource-level permissions; the namespace condition scopes it
  count = local.scale_to_zero ? 1 : 0

  name   = "${var.service_name}-activity-metrics"
  role   = aws_iam_role.app_service.id
  policy = data.aws_iam_policy_document.activity_metrics.json
}

resource "aws_cloudwatch_metric_alarm" "sleep" {
  count = local.scale_to_zero ? 1 : 0

  alarm_name        = "${var.service_name}-sleep-when-idle"
  alarm_description = "No CBV flows started or invitations created for ${var.scale_to_zero_idle_hours}h: scale web and worker to 0."

  namespace   = "VMI/Activity"
  metric_name = "FlowsAndInvitationsCreated"
  dimensions = {
    ServiceName = var.service_name
  }
  statistic           = "Sum"
  period              = local.activity_alarm_period
  evaluation_periods  = var.scale_to_zero_idle_hours * 3600 / local.activity_alarm_period
  threshold           = 0.5 # counts are whole numbers: "< 0.5" means 0
  comparison_operator = "LessThanThreshold"

  # Missing data means no web task is running: either already asleep, or just
  # woken. Treating it as not idle means a freshly woken environment needs a
  # full scale_to_zero_idle_hours of published zeros before it sleeps again.
  treat_missing_data = "notBreaching"

  alarm_actions = [
    aws_appautoscaling_policy.web_sleep[0].arn,
    aws_appautoscaling_policy.worker_sleep[0].arn,
  ]
}

resource "aws_appautoscaling_policy" "web_sleep" {
  count = local.scale_to_zero ? 1 : 0

  name               = "${var.service_name}-sleep"
  policy_type        = "StepScaling"
  service_namespace  = aws_appautoscaling_target.web.service_namespace
  resource_id        = aws_appautoscaling_target.web.resource_id
  scalable_dimension = aws_appautoscaling_target.web.scalable_dimension

  step_scaling_policy_configuration {
    adjustment_type = "ExactCapacity"
    cooldown        = 60

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = 0
    }
  }
}

resource "aws_appautoscaling_policy" "worker_sleep" {
  count = local.scale_to_zero ? 1 : 0

  name               = "${var.service_name}-worker-sleep"
  policy_type        = "StepScaling"
  service_namespace  = aws_appautoscaling_target.worker[0].service_namespace
  resource_id        = aws_appautoscaling_target.worker[0].resource_id
  scalable_dimension = aws_appautoscaling_target.worker[0].scalable_dimension

  step_scaling_policy_configuration {
    adjustment_type = "ExactCapacity"
    cooldown        = 60

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = 0
    }
  }
}

#---------------------------------------------------------------------------
# Wake: a request to a user-facing path
#---------------------------------------------------------------------------

# Count-only web ACL: it never blocks or alters a request. It exists because
# WAF publishes a per-rule request count even when the target group has no
# tasks, whereas the load balancer's own metrics can't tell paths apart then.
resource "aws_wafv2_web_acl" "wake" {
  # checkov:skip=CKV2_AWS_31:WAF logging not needed; this ACL only counts requests to drive scale-to-zero wake-up
  # checkov:skip=CKV_AWS_192:Not a protective ACL; it only counts requests to drive scale-to-zero wake-up
  count = local.scale_to_zero ? 1 : 0

  name        = "${var.service_name}-wake"
  description = "Counts requests to user-facing paths to wake the scaled-to-zero service. Never blocks."
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "count-wake-requests"
    priority = 0

    action {
      count {}
    }

    statement {
      or_statement {
        # /start (generic links) and /start/:token (invitation links)
        statement {
          byte_match_statement {
            search_string         = "/start"
            positional_constraint = "STARTS_WITH"
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }

        # The flow itself, e.g. a person reloading a page while it wakes up
        statement {
          byte_match_statement {
            search_string         = "/cbv/"
            positional_constraint = "STARTS_WITH"
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }

        # Invitation creation through the partner API
        statement {
          and_statement {
            statement {
              byte_match_statement {
                search_string         = "/api/v1/invitations"
                positional_constraint = "STARTS_WITH"
                field_to_match {
                  uri_path {}
                }
                text_transformation {
                  priority = 0
                  type     = "LOWERCASE"
                }
              }
            }
            statement {
              byte_match_statement {
                search_string         = "POST"
                positional_constraint = "EXACTLY"
                field_to_match {
                  method {}
                }
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = local.wake_rule_metric_name
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.service_name}-wake"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "wake" {
  count = local.scale_to_zero ? 1 : 0

  resource_arn = aws_lb.alb.arn
  web_acl_arn  = aws_wafv2_web_acl.wake[0].arn
}

resource "aws_cloudwatch_metric_alarm" "wake" {
  count = local.scale_to_zero ? 1 : 0

  alarm_name        = "${var.service_name}-wake-on-request"
  alarm_description = "A request to a user-facing path (/start, /cbv/, POST /api/v1/invitations): scale web and worker to 1."

  namespace   = "AWS/WAFV2"
  metric_name = "CountedRequests"
  dimensions = {
    WebACL = aws_wafv2_web_acl.wake[0].name
    Rule   = local.wake_rule_metric_name
    Region = data.aws_region.current.name
  }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0.5 # counts are whole numbers: "> 0.5" means at least 1
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  # Setting exactly 1 is safe to repeat while people keep using the app: the
  # alarm stays in ALARM and the policies re-run, but capacity is already 1.
  alarm_actions = [
    aws_appautoscaling_policy.web_wake[0].arn,
    aws_appautoscaling_policy.worker_wake[0].arn,
  ]
}

resource "aws_appautoscaling_policy" "web_wake" {
  count = local.scale_to_zero ? 1 : 0

  name               = "${var.service_name}-wake"
  policy_type        = "StepScaling"
  service_namespace  = aws_appautoscaling_target.web.service_namespace
  resource_id        = aws_appautoscaling_target.web.resource_id
  scalable_dimension = aws_appautoscaling_target.web.scalable_dimension

  step_scaling_policy_configuration {
    adjustment_type = "ExactCapacity"
    cooldown        = 60

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }
}

resource "aws_appautoscaling_policy" "worker_wake" {
  count = local.scale_to_zero ? 1 : 0

  name               = "${var.service_name}-worker-wake"
  policy_type        = "StepScaling"
  service_namespace  = aws_appautoscaling_target.worker[0].service_namespace
  resource_id        = aws_appautoscaling_target.worker[0].resource_id
  scalable_dimension = aws_appautoscaling_target.worker[0].scalable_dimension

  step_scaling_policy_configuration {
    adjustment_type = "ExactCapacity"
    cooldown        = 60

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }
}
