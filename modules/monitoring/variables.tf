variable "name_prefix" {
  description = "Naming prefix for alarms (e.g. 'ringr-sip-prod')."
  type        = string
}

variable "nlb_arn_suffix" {
  description = "NLB ARN suffix (net/<name>/<id>). Output of the nlb module."
  type        = string
}


variable "tg_sip_tcp_arn_suffix" {
  description = "TCP target group ARN suffix. Output of the nlb module."
  type        = string
}

variable "tg_sip_tls_arn_suffix" {
  description = "TLS target group ARN suffix. Output of the nlb module."
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name. Output of the ecs module."
  type        = string
}

variable "ecs_service_tcp_name" {
  description = "Name of the ECS TCP/TLS service. Output of the ecs module."
  type        = string
}


variable "rds_identifier" {
  description = "RDS instance identifier. Output of the rds module."
  type        = string
}

variable "rds_free_storage_alarm_gb" {
  description = "Free storage threshold in GB below which the RDS alarm fires. Recommended: 5 (prod), 2 (nonprod)."
  type        = number
  default     = 5
}

variable "alarm_actions" {
  description = <<-EOT
    List of SNS topic ARNs to notify when an alarm fires.
    Leave empty to create alarms without notifications (useful during initial setup).
    Example: ["arn:aws:sns:eu-west-1:123456789:ringr-sip-alerts"]
  EOT
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Common tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
