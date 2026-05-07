locals {
  stack_id_provided = length(trimspace(var.stack_id)) > 0
  stack_id          = local.stack_id_provided ? var.stack_id : substr(random_id.stack[0].hex, 0, 8)

  service_id_name   = "salt-security-sid-${local.stack_id}"
  api_key_name      = "salt-security-key-${local.stack_id}"
  access_group_name = "salt-security-ag-${local.stack_id}"
}

# ----------------------------------------------------------------------------
# Stack ID generation (when not supplied by caller)
# ----------------------------------------------------------------------------
resource "random_id" "stack" {
  count       = local.stack_id_provided ? 0 : 1
  byte_length = 4
}

data "ibm_iam_account_settings" "current" {}

# ============================================================================
# IAM Service ID + API key
#
# Salt's scanner authenticates to IBM Cloud using the API key bound to this
# Service ID. At scan time the scanner exchanges the key for a short-lived
# IAM bearer token at iam.cloud.ibm.com/identity/token.
#
# IBM IAM does not currently support OIDC or AWS-STS federation for external
# workloads, so a rotatable API key is the practical auth option for a
# scanner running outside IBM Cloud (Salt runs on AWS EKS). Matches the
# Azure ClientSecret pattern used elsewhere in api-collectors.
# ============================================================================

resource "ibm_iam_service_id" "salt" {
  name        = local.service_id_name
  description = "Salt Security read-only Service ID (stack ${local.stack_id})"
}

resource "ibm_iam_service_api_key" "salt" {
  name           = local.api_key_name
  iam_service_id = ibm_iam_service_id.salt.iam_id
  description    = "API key issued to Salt Security for API-Connect discovery"
  store_value    = false
}

# ----------------------------------------------------------------------------
# Access group with least-privilege policies scoped to IBM API Connect only.
# Permissions live on the group (not the Service ID directly) so they can be
# updated without re-issuing the key.
#
# Scope matches the AWS-side precedent in
# cloud-connect-deployments/aws/manual-setup/discovery-policy.json, which
# grants apigateway:GET on Resource:* — i.e., read-only on exactly one
# service, nothing else.
#
# Two policies are required (dropping either breaks the scan):
#   1. Platform Viewer — lets the Service ID see the API Connect instance
#      exists in the Resource Controller (needed to traverse the
#      provider-orgs → catalogs → spaces → APIs hierarchy)
#   2. Service Reader — lets the Service ID call the API Connect management
#      APIs (list providers/catalogs/APIs, export OpenAPI specs)
#
# Both are constrained to serviceName = "apiconnect" so the key cannot read
# anything else in the customer's account — no IAM users, no COS buckets, no
# Kubernetes clusters, etc.
# ----------------------------------------------------------------------------

resource "ibm_iam_access_group" "salt" {
  name        = local.access_group_name
  description = "Read-only access to IBM API Connect for Salt Security Service ID"
}

resource "ibm_iam_access_group_members" "salt" {
  access_group_id = ibm_iam_access_group.salt.id
  iam_service_ids = [ibm_iam_service_id.salt.id]
}

resource "ibm_iam_access_group_policy" "apiconnect" {
  access_group_id = ibm_iam_access_group.salt.id
  roles           = ["Viewer", "Reader"]
  description     = "Read-only access to IBM API Connect (Platform Viewer + Service Reader)"

  # NOTE 1: accountId is injected automatically by the IBM provider from the
  # authenticated session — adding it explicitly causes "invalid_body: The
  # following resource attribute(s) had multiple entries: accountId".
  #
  # NOTE 2: IBM treats (access_group_id, resource_attributes) as the policy
  # uniqueness key — two policies with the same serviceName scope but
  # different roles will 409. Platform + Service roles must be combined in
  # one policy. (Reader here is the *service* Reader; Viewer is the
  # *platform* Viewer — IBM disambiguates based on each role's definition.)
  resources {
    attributes = {
      "serviceName" = "apiconnect"
    }
  }
}

# ----------------------------------------------------------------------------
# Send the freshly-minted API key to the Salt backend.
#
# We use a null_resource + local-exec so the key payload never lands in
# Terraform outputs or the Schematics state viewer. The script writes the
# backend response to a file which we read back via data.local_file for the
# deployment_status output.
# ----------------------------------------------------------------------------
resource "null_resource" "post_credentials" {
  triggers = {
    stack_id   = local.stack_id
    service_id = ibm_iam_service_id.salt.id
    api_key_id = ibm_iam_service_api_key.salt.id
  }

  provisioner "local-exec" {
    command     = "${path.module}/scripts/post_credentials.sh"
    interpreter = ["bash", "-c"]

    environment = {
      SALT_HOST       = var.salt_host
      SALT_AUTH_TOKEN = var.salt_auth_token
      STACK_ID        = local.stack_id
      ENVIRONMENT_ID  = var.environment_id
      ACCOUNT_ID      = data.ibm_iam_account_settings.current.account_id
      IBM_API_KEY     = ibm_iam_service_api_key.salt.apikey
      STATUS_FILE     = "${path.module}/.deployment_status"
    }
  }

  depends_on = [
    ibm_iam_access_group_policy.apiconnect,
    ibm_iam_access_group_members.salt,
  ]
}

data "local_file" "post_result" {
  filename = "${path.module}/.deployment_status"

  depends_on = [null_resource.post_credentials]
}