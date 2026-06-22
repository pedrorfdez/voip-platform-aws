variable "name_prefix" {
  description = "Naming and tagging prefix for all resources in this module (e.g. 'ringr-sip-prod')."
  type        = string
}

variable "secret_arns" {
  description = <<-EOT
    ARNs of the Secrets Manager secrets the task execution role is allowed to read
    and inject into the container at startup (e.g. RDS credentials).
    If left empty, the permission covers all secrets in the account ("*").
    Pass the specific RDS secret ARN once the rds module exists.
  EOT
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Common tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
