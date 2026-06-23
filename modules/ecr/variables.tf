variable "name_prefix" {
  description = "Naming and tagging prefix for all resources in this module (e.g. 'ringr-sip-nonprod')."
  type        = string
}

variable "image_tag_mutability" {
  description = "Tag mutability for the repository. MUTABLE allows overwriting tags (simpler for dev); IMMUTABLE enforces unique tags per image (safer for prod)."
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "keep_image_count" {
  description = "Number of tagged images to keep per repository. Older images are expired by the lifecycle policy."
  type        = number
  default     = 10
}

variable "tags" {
  description = "Common tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
