variable "environment" {
  description = "Environment name ('prod' or 'nonprod'). Used as the name_prefix suffix and as a tag."
  type        = string
}

variable "aws_region" {
  description = "AWS region where the infrastructure is deployed."
  type        = string
  default     = "eu-west-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR block."
  type        = string
}

variable "availability_zones" {
  description = "List of AZs in which to create subnets (minimum 2)."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs, one per AZ in the same order as availability_zones."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs, one per AZ in the same order as availability_zones."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "true: one shared NAT Gateway (cheaper, less resilient). false: one per AZ (HA, higher cost)."
  type        = bool
}

variable "enable_interface_endpoints" {
  description = "true: create Interface VPC Endpoints (ECR, SSM, Secrets Manager). false: traffic goes via NAT (saves cost in nonprod)."
  type        = bool
}

variable "operator_cidrs" {
  description = "CIDR ranges of authorized SIP operators/trunks. Replace the placeholder with real IPs before deploying."
  type        = list(string)
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the TLS 5061 listener. If empty, port 5061 uses plain TCP (passthrough)."
  type        = string
  default     = ""
}

variable "container_image" {
  description = "Full ECR image URI (e.g. '123456789.dkr.ecr.eu-west-1.amazonaws.com/ringr-sip:latest'). Replace the placeholder before deploying."
  type        = string
}

variable "ecs_task_cpu" {
  description = "Fargate task CPU in units (512 = 0.5 vCPU)."
  type        = number
}

variable "ecs_task_memory" {
  description = "Fargate task memory in MB."
  type        = number
}

variable "ecs_desired_count" {
  description = "Initial number of tasks per ECS service."
  type        = number
}

variable "ecs_min_capacity" {
  description = "Minimum number of tasks per service that auto scaling maintains."
  type        = number
}

variable "ecs_max_capacity" {
  description = "Maximum number of tasks per service that auto scaling can launch."
  type        = number
}

variable "ecs_cpu_scale_target" {
  description = "Target average CPU utilization percentage for auto scaling."
  type        = number
}

variable "ecs_min_healthy_percent" {
  description = "Minimum percentage of healthy tasks during a deployment. 100 = no capacity loss."
  type        = number
}

variable "ecs_max_percent" {
  description = "Maximum percentage of tasks relative to desired_count during a deployment."
  type        = number
}

variable "ecs_log_retention_days" {
  description = "Retention period in days for container logs in CloudWatch."
  type        = number
}

variable "rds_instance_class" {
  description = "RDS instance type (e.g. 'db.t3.micro', 'db.t3.medium')."
  type        = string
}

variable "rds_multi_az" {
  description = "true: standby in a second AZ with automatic failover (prod). false: single instance (nonprod)."
  type        = bool
}

variable "rds_backup_retention_days" {
  description = "Number of days to retain automatic RDS backups."
  type        = number
}

variable "rds_deletion_protection" {
  description = "true: prevents accidental deletion of the instance (enable in prod)."
  type        = bool
}

variable "rds_skip_final_snapshot" {
  description = "false: take a snapshot before destroying the instance (enable in prod)."
  type        = bool
}

variable "rds_performance_insights_enabled" {
  description = "Enables Performance Insights for query analysis. Not available on db.t3.micro."
  type        = bool
}

variable "rds_max_allocated_storage" {
  description = "Storage autoscaling ceiling in GB. 0 disables autoscaling."
  type        = number
}

variable "rds_log_retention_days" {
  description = "Retention period in days for PostgreSQL logs in CloudWatch."
  type        = number
  default     = 30
}

variable "rds_backup_window" {
  description = "Daily RDS backup window in UTC (format 'hh:mm-hh:mm')."
  type        = string
  default     = "03:00-04:00"
}

variable "rds_maintenance_window" {
  description = "Weekly RDS maintenance window in UTC."
  type        = string
  default     = "Mon:04:00-Mon:05:00"
}

variable "nlb_deletion_protection" {
  description = "If true, prevents accidental deletion of the NLB. Enable in prod."
  type        = bool
  default     = false
}

variable "nlb_cross_zone_lb" {
  description = "If true, the NLB routes traffic to targets in any AZ. Enable in nonprod when desired_count=1 to avoid the task being unreachable from the wrong AZ EIP. Keep false in prod."
  type        = bool
  default     = false
}

variable "alarm_actions" {
  description = "SNS topic ARNs for alarm notifications. Empty list = alarms with no notification."
  type        = list(string)
  default     = []
}

variable "rds_free_storage_alarm_gb" {
  description = "Free storage threshold in GB below which the RDS alarm fires."
  type        = number
  default     = 2
}
