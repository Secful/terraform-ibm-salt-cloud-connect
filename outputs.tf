output "stack_id" {
  description = "Auto-generated stack ID used to namespace resources."
  value       = local.stack_id
}

output "account_id" {
  description = "IBM Cloud account ID the Service ID belongs to."
  value       = data.ibm_iam_account_settings.current.account_id
}

output "service_id" {
  description = "IBM IAM Service ID (id form, e.g. ServiceId-xxx) created for Salt Security."
  value       = ibm_iam_service_id.salt.id
}

output "service_id_iam_id" {
  description = "IAM ID of the Service ID (iam-ServiceId-xxx form)."
  value       = ibm_iam_service_id.salt.iam_id
}

output "api_key_id" {
  description = "IBM IAM API key ID bound to the Service ID."
  value       = ibm_iam_service_api_key.salt.id
}

output "api_key" {
  description = "The Service ID API key. Sensitive: consume via `terraform output -raw api_key`; never log."
  value       = ibm_iam_service_api_key.salt.apikey
  sensitive   = true
}

output "access_group_id" {
  description = "Access group containing the Service ID."
  value       = ibm_iam_access_group.salt.id
}