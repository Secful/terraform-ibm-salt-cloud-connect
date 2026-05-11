# Manual-deploy usage: Terraform posts Initiated/Succeeded to the Salt
# backend itself. Use when applying from the Schematics UI without the
# Cloud Shell orchestrator script.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    ibm = {
      source  = "IBM-Cloud/ibm"
      version = "~> 2.1"
    }
  }
}

provider "ibm" {
  # IC_API_KEY env var supplies credentials
}

variable "salt_host" {
  description = "Salt backend URL (e.g. https://api.salt.security)"
  type        = string
}

variable "salt_auth_token" {
  description = "Bearer token from the Salt dashboard"
  type        = string
  sensitive   = true
}

variable "attempt_id" {
  description = "Onboarding attempt UUID from the Salt backend"
  type        = string
}

module "salt_cloud_connect" {
  source = "../.."

  manual_deploy   = true
  salt_host       = var.salt_host
  salt_auth_token = var.salt_auth_token
  attempt_id      = var.attempt_id
}

output "stack_id" {
  value = module.salt_cloud_connect.stack_id
}