locals {
  stack_id = substr(random_id.stack.hex, 0, 8)

  service_id_name   = "salt-security-sid-${local.stack_id}"
  api_key_name      = "salt-security-key-${local.stack_id}"
  access_group_name = "salt-security-ag-${local.stack_id}"
}

resource "random_id" "stack" {
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
}

# ----------------------------------------------------------------------------
# Access group with least-privilege policies scoped to IBM API Connect only.
# Permissions live on the group (not the Service ID directly) so they can be
# updated without re-issuing the key.
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

# Account Management → Viewer: lets the Service ID read account-level
# metadata (most importantly, the account name/alias displayed in the Salt
# dashboard). Account Management services are a separate IAM policy family
# from regular services, so this doesn't collide with the apiconnect policy
# above.
resource "ibm_iam_access_group_policy" "account_management" {
  access_group_id    = ibm_iam_access_group.salt.id
  roles              = ["Viewer"]
  description        = "Read account-level metadata (account name) for Salt dashboard"
  account_management = true
}