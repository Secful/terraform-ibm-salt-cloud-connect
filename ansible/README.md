# Salt Security Cloud Connect — IBM Cloud (Ansible)

Functional equivalent of `../terraform/` with explicit failure reporting to the
Salt backend via Ansible's `block/rescue/always` pattern. Prefer the Terraform
module for Schematics/Catalog onboarding; use this playbook when:

- You need rich failure messages posted to the Salt backend on mid-run errors
- You're running from CI/CD and want imperative control flow
- Your customer's compliance tooling is Ansible-first

## Install

```sh
ansible-galaxy collection install -r requirements.yml
```

## Run

```sh
export IC_API_KEY='your-ibm-cloud-api-key'

ansible-playbook deploy.yml \
  -e salt_host=https://api.salt.security \
  -e salt_auth_token=<token> \
  [-e attempt_id=<uuid>]
```

## What gets created

Same four resources as the Terraform module:

1. `ibm_iam_service_id` — `salt-security-sid-<stack_id>`
2. `ibm_iam_service_api_key` — `salt-security-key-<stack_id>` (`store_value=false`)
3. `ibm_iam_access_group` — `salt-security-ag-<stack_id>`
4. `ibm_iam_access_group_policy` — Viewer + Reader, scoped to `serviceName=apiconnect`

## Backend status flow

Unlike the Terraform module (which relies on backend timeout for failure
detection), this playbook sends three distinct status POSTs:

| When | Status | Body includes |
|------|--------|---------------|
| Start of run | `Initiated` | `connectionFields: null` |
| All resources created | `Succeeded` | `connectionFields.apiKey` |
| Any task fails | `Failed` | `errorMessage` with truncated reason |

The `rescue:` block in `deploy.yml` catches any failure inside the main block
and POSTs `Failed` before the playbook exits non-zero. Failure reporting is
best-effort — if the backend POST itself fails, the original error still
surfaces via the `fail:` task.

## What this doesn't catch

Same edge cases that Azure/GCP shell scripts miss:

- `kill -9` on the `ansible-playbook` process
- OOM during execution
- Network partition preventing both the IBM API call *and* the Salt callback

For these, Salt's backend still needs a timeout-based transition on stale
`Initiated` records as a safety net.

## Cleanup

No destroy playbook yet. For now, remove the Service ID via the IBM Cloud
console or CLI:

```sh
ibmcloud iam service-id-delete salt-security-sid-<stack_id>
ibmcloud iam access-group-delete salt-security-ag-<stack_id>
```

## Caveats

- **Not tested end-to-end in this commit.** First real run may surface field-name
  mismatches in `ibm.cloudcollection` — module arguments have shifted between
  collection versions. Verify against your installed collection's docs:
  `ansible-doc ibm.cloudcollection.ibm_iam_service_id`.
- **`installation_id` is auto-generated per run.** If Salt's backend uses it
  to route to a specific tenant, pass it explicitly via `-e`.
- **`stack_id` uses `lookup('password', '/dev/null chars=hex length=8')`** —
  which generates on every run. Re-running the playbook creates a new stack
  rather than reusing the previous one.