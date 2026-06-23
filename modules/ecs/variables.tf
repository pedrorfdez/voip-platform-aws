variable "name_prefix" {
  description = "Naming and tagging prefix for all resources in this module (e.g. 'ringr-sip-prod')."
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs of the private subnets where Fargate tasks run."
  type        = list(string)
}

variable "sip_sg_id" {
  description = "Security Group ID for the SIP component (from the security_groups module)."
  type        = string
}

variable "task_execution_role_arn" {
  description = "ARN of the task execution role (used by the ECS agent to pull ECR images and read secrets)."
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the task role (used by the SIP application code)."
  type        = string
}

variable "tg_sip_tcp_arn" {
  description = "ARN of the TCP 5060 target group (from the nlb module)."
  type        = string
}

variable "tg_sip_tls_arn" {
  description = "ARN of the TCP/TLS 5061 target group (from the nlb module)."
  type        = string
}


variable "container_image" {
  description = "Full URI of the SIP container image in ECR (e.g. '123456789.dkr.ecr.eu-west-1.amazonaws.com/ringr-sip:latest')."
  type        = string

  validation {
    condition     = var.container_image != "PLACEHOLDER"
    error_message = "container_image must be a valid image URI (ECR or another registry). Replace 'PLACEHOLDER' with the actual URI before deploying."
  }
}

variable "container_environment" {
  description = "Non-sensitive environment variables for the container (e.g. DB_HOST, DB_PORT)."
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "container_secrets" {
  description = <<-EOT
    Secrets injected from Secrets Manager or SSM Parameter Store.
    Each entry has name (environment variable name) and valueFrom
    (secret ARN, or ARN with a :key:: suffix to extract a JSON field).
    Example: { name = "DB_PASSWORD", valueFrom = "arn:aws:secretsmanager:...:secret:name:password::" }
  EOT
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "task_cpu" {
  description = <<-EOT
    Fargate task CPU in units (1 vCPU = 1024).
    Valid combinations with task_memory: 256→512-2048, 512→1024-4096,
    1024→2048-8192, 2048→4096-16384, 4096→8192-30720.
  EOT
  type        = number
  default     = 512
}

variable "task_memory" {
  description = "Fargate task memory in MB."
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Initial number of tasks per service. Auto scaling adjusts this at runtime."
  type        = number
  default     = 2
}

variable "min_capacity" {
  description = "Minimum number of tasks per service that auto scaling can leave running."
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum number of tasks per service that auto scaling can launch."
  type        = number
  default     = 10
}

variable "cpu_scale_target" {
  description = "Target average CPU utilization percentage for auto scaling. Scales up above this value; scales in below it."
  type        = number
  default     = 70
}

variable "deployment_min_healthy_percent" {
  description = "Minimum percentage of healthy tasks that must be running during a deployment. 100 guarantees no capacity loss."
  type        = number
  default     = 100
}

variable "deployment_max_percent" {
  description = "Maximum percentage of tasks relative to desired_count that can run during a deployment. 200 allows new tasks to start before old ones stop."
  type        = number
  default     = 200
}

variable "log_retention_days" {
  description = "Retention period in days for container logs in CloudWatch."
  type        = number
  default     = 30
}

variable "health_check_grace_period_seconds" {
  description = <<-EOT
    Seconds ECS waits before evaluating health checks after launching a task.
    If the SIP server takes longer than this to become ready (DB connect, route table
    load, etc.), ECS will kill the task before it is healthy and the service will enter
    a restart loop.
    Fargate supports up to 2147483647 s; practical range: 60–300 s.
  EOT
  type        = number
  default     = 120
}

variable "container_stop_timeout" {
  description = <<-EOT
    Seconds ECS waits for the container to exit cleanly after sending SIGTERM.
    During this window the container must close active SIP sessions (send BYE/200 OK).
    The ECS agent sends SIGKILL after this period; any in-progress SIP session is left
    in an inconsistent state.
    Fargate maximum: 120 s. The ECS agent default is 30 s, which is insufficient for long sessions.
  EOT
  type        = number
  default     = 120

  validation {
    condition     = var.container_stop_timeout >= 2 && var.container_stop_timeout <= 120
    error_message = "container_stop_timeout must be between 2 and 120 seconds (Fargate limit)."
  }
}

variable "enable_execute_command" {
  description = "Enables ECS Exec to open a shell into a running container without SSH (via SSM)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
