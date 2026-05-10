# Minimal usage: the module takes no inputs. An external orchestrator
# (e.g. ibm-connect-onboard.sh) reads the outputs and posts them to the
# Salt backend.

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

module "salt_cloud_connect" {
  source = "../.."
}

output "api_key" {
  value     = module.salt_cloud_connect.api_key
  sensitive = true
}

output "stack_id" {
  value = module.salt_cloud_connect.stack_id
}