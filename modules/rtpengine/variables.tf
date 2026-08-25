variable "name_prefix" {
  description = "Naming and tagging prefix for all resources in this module (e.g. 'ringr-sip-nonprod')."
  type        = string
}

variable "private_subnet_id" {
  description = "ID of the private subnet where the rtpengine EC2 instance is placed. Use a single subnet — rtpengine is stateful and must not be split across AZs without sticky routing."
  type        = string
}

variable "rtpengine_sg_id" {
  description = "Security Group ID for the rtpengine instance (defined in modules/security_groups)."
  type        = string
}

variable "rtp_port_min" {
  description = "Lower bound of the UDP port range allocated for RTP streams (one port pair per active call)."
  type        = number
  default     = 10000
}

variable "rtp_port_max" {
  description = "Upper bound of the UDP port range allocated for RTP streams."
  type        = number
  default     = 20000
}

variable "instance_type" {
  description = "EC2 instance type. t3.micro handles tens of concurrent calls; scale up for production load."
  type        = string
  default     = "t3.micro"
}

variable "tags" {
  description = "Common tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
