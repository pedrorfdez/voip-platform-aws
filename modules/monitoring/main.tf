
resource "aws_cloudwatch_metric_alarm" "nlb_unhealthy_tcp" {
  alarm_name          = "${var.name_prefix}-nlb-unhealthy-tcp"
  alarm_description   = "Unhealthy TCP targets on the NLB. SIP TCP traffic is being dropped."
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = 1
  period              = 60
  statistic           = "Maximum"
  namespace           = "AWS/NetworkELB"
  metric_name         = "UnHealthyHostCount"

  dimensions = {
    LoadBalancer = var.nlb_arn_suffix
    TargetGroup  = var.tg_sip_tcp_arn_suffix
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = merge(var.tags, { Name = "${var.name_prefix}-alarm-nlb-unhealthy-tcp" })
}

resource "aws_cloudwatch_metric_alarm" "nlb_unhealthy_tls" {
  alarm_name          = "${var.name_prefix}-nlb-unhealthy-tls"
  alarm_description   = "Unhealthy TLS targets on the NLB. SIP TLS traffic is being dropped."
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = 1
  period              = 60
  statistic           = "Maximum"
  namespace           = "AWS/NetworkELB"
  metric_name         = "UnHealthyHostCount"

  dimensions = {
    LoadBalancer = var.nlb_arn_suffix
    TargetGroup  = var.tg_sip_tls_arn_suffix
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = merge(var.tags, { Name = "${var.name_prefix}-alarm-nlb-unhealthy-tls" })
}

resource "aws_cloudwatch_metric_alarm" "rds_low_storage" {
  alarm_name          = "${var.name_prefix}-rds-low-storage"
  alarm_description   = "RDS free storage below ${var.rds_free_storage_alarm_gb} GB. Risk of imminent read-only mode."
  comparison_operator = "LessThanThreshold"
  threshold           = var.rds_free_storage_alarm_gb * 1024 * 1024 * 1024
  evaluation_periods  = 2
  period              = 300
  statistic           = "Minimum"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"

  dimensions = {
    DBInstanceIdentifier = var.rds_identifier
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = merge(var.tags, { Name = "${var.name_prefix}-alarm-rds-low-storage" })
}

resource "aws_cloudwatch_metric_alarm" "rds_high_cpu" {
  alarm_name          = "${var.name_prefix}-rds-high-cpu"
  alarm_description   = "RDS CPU above 80% for 10 minutes. May indicate slow queries or lock contention."
  comparison_operator = "GreaterThanThreshold"
  threshold           = 80
  evaluation_periods  = 2
  period              = 300
  statistic           = "Average"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"

  dimensions = {
    DBInstanceIdentifier = var.rds_identifier
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = merge(var.tags, { Name = "${var.name_prefix}-alarm-rds-high-cpu" })
}

