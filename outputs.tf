output "stack_id" {
  description = "Auto-generated stack ID used to namespace resources."
  value       = local.stack_id
}

output "service_id" {
  description = "IBM IAM Service ID created for Salt Security. The API key bound to this Service ID is posted to the Salt backend and is NOT exposed as a Terraform output."
  value       = ibm_iam_service_id.salt.id
}

output "account_id" {
  description = "IBM Cloud account ID the Service ID belongs to."
  value       = data.ibm_iam_account_settings.current.account_id
}

output "deployment_status" {
  description = "Terminal status of the Salt backend POST. 'succeeded' means credentials were accepted."
  value       = trimspace(data.local_file.post_result.content)
}