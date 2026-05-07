
variable "salt_host" {
  description = "Salt Security backend host URL (e.g., https://api.salt.security)."
  type        = string

  validation {
    condition     = can(regex("^https?://", var.salt_host))
    error_message = "salt_host must start with http:// or https://."
  }
}

variable "salt_auth_token" {
  description = "Bearer token for the Salt Security backend. Sent in the Authorization header; never stored in outputs."
  type        = string
  sensitive   = true
}

variable "stack_id" {
  description = "Deployment stack ID used to namespace IBM resources (8-char hex recommended). Auto-generated if empty."
  type        = string
  default     = ""
}

variable "environment_id" {
  description = "Salt environment/installation ID. Forwarded to the backend on the status POST."
  type        = string
  default     = ""
}

variable "ibm_region" {
  description = "IBM Cloud region for provider API calls. IAM is global; this primarily affects resource-controller API routing."
  type        = string
  default     = "us-south"
}