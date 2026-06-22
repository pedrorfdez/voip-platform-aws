variable "name_prefix" {
  description = "Naming and tagging prefix for all resources in this module (e.g. 'ringr-sip-prod')."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where the NLB lives."
  type        = string
}

variable "public_subnets_by_az" {
  description = "Map of { az => subnet_id } for public subnets. Same output as the network module."
  type        = map(string)
}

variable "nlb_sg_id" {
  description = "Security Group ID of the NLB (from the security_groups module)."
  type        = string
}

variable "certificate_arn" {
  description = <<-EOT
    ACM certificate ARN for the TLS listener on port 5061.
    If provided, the NLB terminates TLS and forwards plain TCP to the container.
    If left empty, port 5061 uses plain TCP (passthrough: the container terminates TLS itself).
  EOT
  type        = string
  default     = ""
}

variable "health_check_port" {
  description = <<-EOT
    TCP port used for health checks on the TCP and TLS target groups.
    "traffic-port" uses the same port number as the listener (5060 and 5061).
  EOT
  type        = string
  default     = "traffic-port"
}

variable "udp_health_check_port" {
  description = <<-EOT
    TCP port used for the health check of the UDP 5060 target group.

    CRITICAL: NLBs do not support UDP health checks. This health check sends a TCP
    connection to the specified port. The SIP server MUST have a TCP socket listening
    on this port; otherwise all UDP targets are permanently marked unhealthy and the
    NLB silently drops all UDP SIP traffic with no alarm.

    Options:
      "traffic-port"  → TCP to 5060 (requires the SIP server to open TCP 5060)
      "8080"          → dedicated HTTP health-check port (more robust)

    Confirm with the SIP application team which TCP port they expose for health checks
    before using the default value.
  EOT
  type        = string
  default     = "traffic-port"
}

variable "health_check_interval" {
  description = "Seconds between health checks. NLBs only allow 10 or 30."
  type        = number
  default     = 30

  validation {
    condition     = contains([10, 30], var.health_check_interval)
    error_message = "NLBs only support health check intervals of 10 or 30 seconds."
  }
}

variable "health_check_threshold" {
  description = <<-EOT
    Number of consecutive health checks required to mark a target healthy or unhealthy.
    NLBs require the healthy and unhealthy thresholds to be equal (between 2 and 10).
  EOT
  type        = number
  default     = 3

  validation {
    condition     = var.health_check_threshold >= 2 && var.health_check_threshold <= 10
    error_message = "health_check_threshold must be between 2 and 10."
  }
}

variable "deregistration_delay" {
  description = <<-EOT
    Seconds the NLB waits before removing a deregistering target.
    Allows active SIP sessions to finish before the container stops receiving traffic.
    SIP sessions can last hours; tune this if in-flight calls during deployments are critical.
    AWS accepts 0 to 3600 seconds.
  EOT
  type        = number
  default     = 300

  validation {
    condition     = var.deregistration_delay >= 0 && var.deregistration_delay <= 3600
    error_message = "deregistration_delay must be between 0 and 3600 seconds (AWS target group limit)."
  }
}

variable "enable_deletion_protection" {
  description = <<-EOT
    If true, prevents deleting the NLB from the console or with terraform destroy.
    Enable in prod: deleting the NLB causes an immediate outage for all SIP traffic.
    Disable in nonprod to allow terraform destroy without extra steps.
  EOT
  type        = bool
  default     = false
}

variable "enable_cross_zone_load_balancing" {
  description = <<-EOT
    If true, the NLB can route traffic to targets in any AZ, not only the AZ where
    the packet arrived. For stateful SIP (session state in memory) keep false (NLB default):
    it pins the session to the same AZ and minimizes latency. Enable only if there is a
    severe load imbalance across AZs.
  EOT
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
