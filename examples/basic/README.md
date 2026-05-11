# basic

Minimal example: apply the module with the three required variables
(`salt_host`, `salt_auth_token`, `attempt_id`). Terraform itself POSTs
`Initiated` before IAM creation and `Succeeded` after, so the Salt backend
is kept in sync without any external orchestrator.

```sh
export IC_API_KEY='your-ibm-cloud-api-key'

terraform init
terraform apply \
  -var salt_host=https://api.salt.security \
  -var salt_auth_token=<token> \
  -var attempt_id=<uuid>
```

## Security note

`salt_auth_token` is a bearer token that gets recorded in Terraform state
because it's passed to a `local-exec` provisioner. Treat it like any other
secret — restrict state file access, and rotate the token if the state
file is compromised.