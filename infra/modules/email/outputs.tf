output "newrelic_api_destination_arn" {
  description = "EventBridge API destination that posts custom events to New Relic. Reused by other EventBridge rules (e.g. autoscaling notifications)."
  value       = aws_cloudwatch_event_api_destination.newrelic.arn
}
