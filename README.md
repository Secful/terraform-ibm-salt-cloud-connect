# terraform-ibm-salt-cloud-connect

Terraform module that creates the IBM Cloud IAM resources Salt Security's
scanner needs to read your API Connect metadata, and reports deployment
status to the Salt backend as it runs.

Terraform always POSTs `Initiated` to the Salt backend before creating any
IAM, and `Succeeded` (with the API key in `connectionFields`) once the
access group and policies are wired up. An apply either lands both
notifications or aborts — so the backend never sees IAM resources it
doesn't know about. Callers (the Cloud Shell orchestrator in the parent
repo, or a customer applying from the Schematics UI) don't need to POST
anything themselves; they just run `apply`.

## What it creates

| Resource                       | Name                                  | Scope                    |
| ------------------------------ | ------------------------------------- | ------------------------ |
| `ibm_iam_service_id`           | `salt-security-sid-<stack_id>`        | —                        |
| `ibm_iam_service_api_key`      | `salt-security-key-<stack_id>`        | —                        |
| `ibm_iam_access_group`         | `salt-security-ag-<stack_id>`         | —                        |
| `ibm_iam_access_group_members` | Service ID → access group             | —                        |
| `ibm_iam_access_group_policy`  | Viewer + Reader                       | `serviceName=apiconnect` |
| `ibm_iam_access_group_policy`  | Viewer                                | Account Management       |

`stack_id` is an auto-generated 8-char hex suffix.

## Inputs

| Variable           | Required | Description                                           |
| ------------------ | -------- | ----------------------------------------------------- |
| `salt_host`        | ✅       | Salt backend URL (e.g. `https://api.salt.security`)   |
| `salt_auth_token`  | ✅       | Bearer token from the Salt dashboard (sensitive)      |
| `attempt_id`       | ✅       | Onboarding attempt UUID from the Salt backend         |
| `installation_id`  |          | Salt tenant/installation UUID                         |

All three required variables are validated at plan time.

> **Note on Schematics behavior:** Schematics runs Terraform in a sandboxed
> container and rewrites every `local-exec` provisioner to `safe-local-exec`
> in its apply logs. The `local-exec` in this module's `main.tf` is the same
> thing — Schematics is just labelling it for transparency.

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

## Security considerations

- **`salt_auth_token` lives in Terraform state.** It's passed to a
  `local-exec` provisioner, which means it's recorded in
  `terraform.tfstate`. For Schematics deployments the state is encrypted at
  rest, but anyone with workspace read access can retrieve it. Treat the
  token like any other secret.
- **`api_key` is displayed in plaintext on the Schematics Outputs tab.**
  Marking an output `sensitive = true` hides it from the Terraform CLI, but
  Schematics' UI shows it anyway. **Do not grant workspace viewer access to
  anyone you wouldn't give the API key to.** If you need to share workspace
  access with other IAM identities, consider running `terraform destroy`
  and re-deploying after the collaboration ends.
- **Minimum-trust scope by design** — see [Least-privilege scope](#least-privilege-scope).

## Region

IBM IAM is account-scoped (global), not regional. The Service ID, API key,
access group, and policies this module creates apply **across every IBM
region** where the customer has API Connect instances — no per-region
deployment needed. The region the Schematics workspace runs in is cosmetic
(metadata/billing-locality only).

## Least-privilege scope

The access group grants **read-only access to IBM API Connect, plus
read-only visibility of account-level metadata (account name) — and nothing
else**. The Service ID cannot read:

- IAM users, Service IDs, access groups, policies
- Cloud Object Storage buckets or objects
- Kubernetes (IKS/ROKS) clusters, secrets, or workloads
- VPC networking, Virtual Servers, or any other IBM service

The apiconnect policy combines two roles because IBM IAM splits
responsibilities: Platform Viewer lets the Service ID see that the API
Connect instance exists (needed to traverse the provider-orgs → catalogs →
spaces → APIs hierarchy), and Service Reader lets it call the API Connect
management APIs to export OpenAPI specs.

The Account Management Viewer policy is a separate IAM policy family and
exists so Salt's dashboard can display the customer's IBM account name
alongside scan results.

## Prerequisites

### IBM Cloud account

- Pay-As-You-Go or higher — the Lite tier cannot create Service IDs.

### IAM permissions the caller needs

The user (or Service ID) running `terraform apply` must have permission to
create, read, and delete the resources this module manages. The simplest
grant is the **Administrator** role on the following platform services at
the account scope:

| Service / scope                        | Role            | Why                                         |
| -------------------------------------- | --------------- | ------------------------------------------- |
| IAM Identity Service                   | Administrator   | Create/delete the Service ID and API key    |
| IAM Access Groups Service              | Administrator   | Create/delete the access group + policies   |
| All Account Management Services        | Administrator   | Assign the Account Management Viewer policy |
| All Identity and Access enabled services | Viewer       | `data.ibm_iam_account_settings` read        |

A narrower (but harder to specify) alternative is the Account Owner IBMid,
which implicitly has all of the above.

### CLI / tooling

- `terraform` ≥ 1.9.0 (for local use)
- `ibmcloud` CLI (for Schematics use — pre-installed in IBM Cloud Shell)
- `IC_API_KEY` env var set (for local dev) or a Schematics workspace
  with credentials configured

## Local use

```sh
export IC_API_KEY='your-ibm-cloud-api-key'

terraform init
terraform fmt -check
terraform validate
terraform apply \
  -var salt_host=https://api.salt.security \
  -var salt_auth_token=<token> \
  -var attempt_id=<uuid>

# Hand the API key to your orchestration:
terraform output -raw api_key
```

See [`examples/basic`](examples/basic) for a copy-paste template.

## Schematics use

Create a Schematics workspace pointing at this repo:

```
Repository URL:     https://github.com/Secful/terraform-ibm-salt-cloud-connect
Terraform version:  terraform_v1.13
```

Set the following variables in the workspace (whether the apply is driven
by the Cloud Shell orchestrator or triggered manually from the Schematics
UI):

| Variable          | Value                                               |
| ----------------- | --------------------------------------------------- |
| `salt_host`       | Salt backend URL (from Salt dashboard)              |
| `salt_auth_token` | Bearer token (paste into the Schematics form)       |
| `attempt_id`      | Onboarding attempt UUID (from Salt dashboard)       |

Apply. Terraform POSTs `Initiated` before IAM creation and `Succeeded` after.

## Cleanup

### Local Terraform

```sh
terraform destroy
```

### Schematics

```sh
ibmcloud schematics destroy --id <workspace_id> --force
ibmcloud schematics workspace delete --id <workspace_id> --force
```

Or use the companion offboarding script
(`ibm/single_account/ibm-connect-offboard.sh` in the parent repo), which
drives both commands and notifies the Salt backend.

Either cleanup path removes the Service ID, API key, access group, and
policies.

## License

Apache License 2.0 — see [LICENSE](LICENSE).