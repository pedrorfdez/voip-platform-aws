variable "name_prefix" {
  description = "Naming and tagging prefix for all resources in this module (e.g. 'ringr-sip-prod')."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block (e.g. '10.0.0.0/16'). Must be a private RFC 1918 range."
  type        = string

  validation {
    condition = can(cidrhost(var.vpc_cidr, 0)) && anytrue([
      startswith(var.vpc_cidr, "10."),
      can(regex("^172\\.(1[6-9]|2[0-9]|3[01])\\.", var.vpc_cidr)),
      startswith(var.vpc_cidr, "192.168."),
    ])
    error_message = "vpc_cidr must be a private IPv4 CIDR (RFC 1918): 10.0.0.0/8, 172.16.0.0/12, or 192.168.0.0/16."
  }
}

variable "availability_zones" {
  description = "AZs in which to create subnets. The design assumes at least 2 for high availability."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 AZs are required for high availability."
  }
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
  description = <<-EOT
    If true, creates one shared NAT Gateway for all AZs (cheaper, less resilient).
    If false, creates one NAT Gateway per AZ (high availability, higher cost).
    Typical pattern: false in prod, true in nonprod.
  EOT
  type        = bool
  default     = false
}

variable "aws_region" {
  description = "AWS region. Used to construct VPC Endpoint service names."
  type        = string
}

variable "enable_interface_endpoints" {
  description = <<-EOT
    If true, creates Interface VPC Endpoints for ECR, CloudWatch Logs, SSM, and Secrets Manager.
    Recommended in prod: traffic to AWS services never traverses the internet or the NAT Gateway.
    In nonprod this can be disabled to avoid the per-hour cost per endpoint per AZ
    (~$0.01/hour per endpoint per AZ). The S3 Gateway endpoint is always created: it is free
    and required by ECR to pull images.
  EOT
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
