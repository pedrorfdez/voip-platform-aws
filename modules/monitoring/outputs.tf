output "alarm_arns" {
  description = "ARNs of all CloudWatch alarms created by this module."
  value = [
    aws_cloudwatch_metric_alarm.nlb_unhealthy_udp.arn,
    aws_cloudwatch_metric_alarm.nlb_unhealthy_tcp.arn,
    aws_cloudwatch_metric_alarm.nlb_unhealthy_tls.arn,
    aws_cloudwatch_metric_alarm.rds_low_storage.arn,
    aws_cloudwatch_metric_alarm.rds_high_cpu.arn,
    aws_cloudwatch_metric_alarm.ecs_service_divergence.arn,
  ]
}
