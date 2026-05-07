# terraform-ibm-salt-cloud-connect

Terraform module that creates the IBM Cloud IAM resources Salt Security's
scanner needs to read your API Connect metadata. Intentionally **pure
provisioning** — no network calls, no provisioners, no Salt-specific inputs.

An orchestrating script (Salt's onboarding flow, or `ibm/onboarding/` in the
parent repo) reads the outputs and POSTs them to the Salt backend.

## What it creates

| Resource                       | Name                                  | Scope                    |
| ------------------------------ | ------------------------------------- | ------------------------ |
| `ibm_iam_service_id`           | `salt-security-sid-<stack_id>`        | —                        |
| `ibm_iam_service_api_key`      | `salt-security-key-<stack_id>`        | —                        |
| `ibm_iam_access_group`         | `salt-security-ag-<stack_id>`         | —                        |
| `ibm_iam_access_group_members` | Service ID → access group             | —                        |
| `ibm_iam_access_group_policy`  | Viewer + Reader combined              | `serviceName=apiconnect` |

`stack_id` is an auto-generated 8-char hex suffix.

## Inputs

**None.** The module is self-contained.

## Outputs

| Output              | Sensitive | Description                                              |
| ------------------- | --------- | -------------------------------------------------------- |
| `stack_id`          |           | 8-char hex namespace for this deployment                 |
| `account_id`        |           | IBM Cloud account ID                                     |
| `service_id`        |           | `ServiceId-<uuid>`                                       |
| `service_id_iam_id` |           | `iam-ServiceId-<uuid>` (the IAM identity form)           |
| `api_key_id`        |           | `ApiKey-<uuid>`                                          |
| `api_key`           | ✅        | The API key value — consume via `terraform output -raw api_key` |
| `access_group_id`   |           | `AccessGroupId-<uuid>`                                   |

## Least-privilege scope

The access group grants **read-only access to IBM API Connect and nothing
else**. Both policies are constrained to `serviceName=apiconnect`, so the
Service ID cannot read:

- IAM users, Service IDs, access groups, policies
- Cloud Object Storage buckets or objects
- Kubernetes (IKS/ROKS) clusters, secrets, or workloads
- VPC networking, Virtual Servers, or any other IBM service

Two policies are required because IBM IAM splits responsibilities: Platform
Viewer lets the Service ID see that the API Connect instance exists (needed
to traverse the provider-orgs → catalogs → spaces → APIs hierarchy), and
Service Reader lets it call the API Connect management APIs to export
OpenAPI specs.

## Prerequisites

- IBM Cloud account (Pay-As-You-Go or higher — the Lite tier cannot create
  Service IDs)
- IBM Cloud user with **IAM Identity Service → Administrator** and
  **access-group admin** permissions
- The `IC_API_KEY` env var set (for local dev) or a Schematics workspace
  with credentials configured

## Local use

```sh
export IC_API_KEY='your-ibm-cloud-api-key'

terraform init
terraform fmt -check
terraform validate
terraform apply

# Hand the API key to your orchestration:
terraform output -raw api_key
```

## Schematics use

Create a Schematics workspace pointing at this repo. No variables need to
be set.

```
Repository URL:     https://github.com/Secful/terraform-ibm-salt-cloud-connect
Terraform version:  terraform_v1.9
```

Apply. The API key is available on the **Resources → Outputs** tab, or via:

```sh
ibmcloud schematics workspace output --id <workspace_id> --output json
```

## Cleanup

```sh
terraform destroy
```

Removes the Service ID, API key, access group, and policies.

## License

Apache License 2.0 — see [LICENSE](LICENSE).