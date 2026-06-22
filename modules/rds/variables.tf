variable "name_prefix" {
  description = "Naming and tagging prefix for all resources in this module (e.g. 'ringr-sip-prod')."
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs of the private subnets where RDS can be placed."
  type        = list(string)
}

variable "rds_sg_id" {
  description = "Security Group ID for the RDS instance (from the security_groups module)."
  type        = string
}

variable "db_name" {
  description = "Name of the database to create inside the instance."
  type        = string
  default     = "ringr_sip"
}

variable "db_username" {
  description = "Master username for the database."
  type        = string
  default     = "sipadmin"
}

variable "engine_version" {
  description = "PostgreSQL major version (AWS pins the latest available patch)."
  type        = string
  default     = "16"
}

variable "instance_class" {
  description = <<-EOT
    RDS instance type. Determines available CPU and memory.
    Examples: db.t3.micro (nonprod, no Performance Insights),
    db.t3.medium (nonprod with real load), db.r7g.large (prod).
  EOT
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Initial storage in GB. Starting point; RDS will grow automatically up to max_allocated_storage if that value is greater than zero."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = <<-EOT
    Maximum GB to which RDS can grow automatically (storage autoscaling).
    Must be greater than allocated_storage. 0 disables autoscaling: if the database
    fills the disk it enters read-only mode and brings down the application.
    Recommended in prod: 100 or more. In nonprod: 0 if data is ephemeral test data.
  EOT
  type        = number
  default     = 0
}

variable "backup_window" {
  description = "Daily automated backup window in UTC (format 'hh:mm-hh:mm'). Must not overlap with maintenance_window."
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Weekly maintenance window in UTC (format 'ddd:hh:mm-ddd:hh:mm'). Must follow backup_window."
  type        = string
  default     = "Mon:04:00-Mon:05:00"
}

variable "multi_az" {
  description = <<-EOT
    If true, RDS maintains a standby replica in another AZ with automatic failover
    (<60s). Required in prod; expensive in nonprod (doubles the instance cost).
  EOT
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain automatic backups. 0 disables backups (not recommended in prod)."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "If true, prevents accidental deletion of the instance from the console or Terraform. Enable in prod."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "If false, RDS takes a snapshot before destroying the instance. Disable in prod."
  type        = bool
  default     = true
}

variable "performance_insights_enabled" {
  description = <<-EOT
    Enables Performance Insights for SQL query performance analysis.
    Not available on db.t3.micro. Enable on larger instance types.
  EOT
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Retention period in days for PostgreSQL and upgrade logs in CloudWatch. Without this, RDS-created log groups have infinite retention."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Common tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
