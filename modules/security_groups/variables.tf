variable "name_prefix" {
  description = "Naming and tagging prefix for all resources in this module (e.g. 'ringr-sip-prod')."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where the security groups are created."
  type        = string
}

variable "operator_cidrs" {
  description = <<-EOT
    CIDR ranges of SIP operators/trunks authorized to reach the NLB.
    Restricting here drops mass port-5060 scanning and toll fraud at the perimeter.
    Use "0.0.0.0/0" only if operators do not have fixed IP addresses.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.operator_cidrs) > 0
    error_message = "At least one operator SIP CIDR is required."
  }
}

variable "tags" {
  description = "Common tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
