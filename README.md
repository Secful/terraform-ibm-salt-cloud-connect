# IBM Cloud Schematics — Salt Security Cloud Connect

Terraform module for giving Salt Security read-only access to IBM Cloud API
Connect resources in your account, deployable through the IBM Cloud console
(IBM Schematics) or locally.

Salt authenticates to IBM Cloud using a rotatable **IAM Service ID API key**
bound to an access group with read-only policies.

This workspace creates:

1. An IAM **Service ID** owned by Salt
2. An **API key** bound to the Service ID (posted to Salt, not exposed in
   Terraform outputs)
3. An **access group** with **Platform Viewer + Service Reader** policies on
   every resource in the account (read-only)
4. Posts the API key to your Salt Security backend

---

## Deploy via IBM Schematics (console)

1. Go to [IBM Cloud Schematics — Create workspace](https://cloud.ibm.com/schematics/workspaces/create).
2. Under **Specify Template**:
   - **Repository URL:** `https://github.com/Secful/terraform-ibm-salt-cloud-connect`
   - **Terraform version:** `terraform_v1.9`
3. Give the workspace a name, region, and resource group, then click **Next**
   → **Create**.
4. On the workspace page, open the **Variables** section and fill in:
   - `salt_host` — Salt backend URL (e.g., `https://api.salt.security`)
   - `salt_auth_token` — bearer token from the Salt onboarding flow
   - `attempt_id` — optional; leave empty to auto-generate
5. Click **Generate plan** → review → **Apply plan**.

Apply takes ~60 seconds. When the workspace flips to "Active" the Service ID
exists and Salt has received the API key.

> The Schematics "Create workspace" page is a two-step form — the variables
> panel only appears *after* the workspace is created and the repo is
> cloned, so variable values can't be pre-filled via URL query parameters.
> Pasting them in on step 4 is the only path.

---

## Variables

| Variable          | Required | Description                                                             |
| ----------------- | -------- | ----------------------------------------------------------------------- |
| `salt_host`       | ✅       | Salt backend base URL, e.g. `https://api.salt.security`                 |
| `salt_auth_token` | ✅       | Bearer token for the Salt backend (sensitive)                           |
| `attempt_id`      |          | Onboarding attempt UUID from the Salt backend. Auto-generated if empty  |

`stack_id`, `installation_id`, `created_by`, and `ibm_region` are all
generated or hardcoded by the module. There's nothing else for the customer
to configure.

---

## What gets created

| Resource                       | Name                                    | Scope                    |
| ------------------------------ | --------------------------------------- | ------------------------ |
| `ibm_iam_service_id`           | `salt-security-sid-<stack_id>`          | —                        |
| `ibm_iam_service_api_key`      | `salt-security-key-<stack_id>`          | —                        |
| `ibm_iam_access_group`         | `salt-security-ag-<stack_id>`           | —                        |
| `ibm_iam_access_group_members` | Service ID → access group               | —                        |
| `ibm_iam_access_group_policy`  | Viewer + Reader combined (see note)     | `serviceName=apiconnect` |

### Least-privilege scope

The access group grants **read-only access to IBM API Connect and nothing
else**. Both policies are constrained to `serviceName=apiconnect`, so the
Service ID cannot read:

- IAM users, Service IDs, access groups, policies
- Cloud Object Storage buckets or objects
- Kubernetes (IKS/ROKS) clusters, secrets, or workloads
- VPC networking, Virtual Servers, or any other IBM service

This mirrors the least-privilege approach Salt uses on other clouds —
read-only on exactly the one service being scanned, nothing else.

Two policies are required because IBM IAM splits responsibilities: Platform
Viewer lets the Service ID see that the API Connect instance exists (needed
to traverse the provider-orgs → catalogs → spaces → APIs hierarchy), and
Service Reader lets it call the API Connect management APIs to export
OpenAPI specs.

---

## Prerequisites

- IBM Cloud account (Pay-As-You-Go or higher — the Lite tier cannot create
  Service IDs)
- IBM Cloud user with **IAM Identity Service → Administrator** and
  **access-group admin** permissions in the target account
- Salt Security backend URL and bearer token (provided at onboarding)

---

## Security notes

- `salt_auth_token` and the generated IBM API key are both marked `sensitive`
  in Terraform — they will not appear in Schematics plan/apply UI logs
- The API key is posted to the Salt backend via `null_resource + local-exec`
  and is never written to Terraform outputs or state as a readable value
  (`store_value = false` on the IBM API key resource)
- All IAM policies are read-only. No `create`, `update`, `delete`, or `set`
  permissions are granted
- Policies are scoped to `serviceName=apiconnect` — the Service ID cannot
  read any IBM resource outside API Connect (see "Least-privilege scope"
  above)
- The Service ID is scoped to *your* account via
  `data.ibm_iam_account_settings.current.account_id` — no cross-account access

### Rotation

To rotate the API key: destroy and re-apply the workspace, or manually
generate a new API key on the existing Service ID (IBM Cloud console →
Service IDs → *salt-security-sid-xxx* → API keys) and paste it into the
Salt dashboard. Automated rotation is tracked as a Phase 2 improvement.

---

## Cleanup

Destroy the workspace from the Schematics console (Actions → Destroy
resources) or locally:

```sh
terraform destroy
```

This removes the Service ID, API key, access group, and policies. It does
**not** deregister the connector from Salt — use the Salt Security dashboard
for that.

---

## Development

```sh
export IC_API_KEY='your-ibm-cloud-api-key'

terraform init
terraform fmt -check
terraform validate
terraform plan \
  -var='salt_host=https://api.salt.security' \
  -var='salt_auth_token=...'
```

The module is designed to be consumed directly by Schematics (no state
backend config needed — Schematics manages state). Local development against
your own IBM account works the same way with an `IC_API_KEY` env var for the
`ibm` provider.

---

## License

Apache License 2.0 — see [LICENSE](LICENSE).