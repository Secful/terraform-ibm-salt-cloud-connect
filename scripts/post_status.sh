#!/usr/bin/env bash
#
# Post a deployment status to the Salt Security Cloud Connect backend.
# Invoked from null_resource.local-exec provisioners when manual_deploy=true.
#
# Required env vars:
#   SALT_HOST          e.g. https://api.salt.security
#   SALT_AUTH_TOKEN    bearer token from the Salt dashboard
#   ATTEMPT_ID         onboarding attempt UUID (Salt-generated)
#   DEPLOYMENT_STATUS  "Initiated" | "Succeeded"
#
# Optional (forwarded only if set):
#   INSTALLATION_ID, STACK_ID, ACCOUNT_ID, SERVICE_ID, API_KEY
#
# Best-effort: a non-2xx response is logged but does NOT fail the apply.
# Rationale: once IAM resources exist, failing the apply on a transient
# network blip would leave orphaned resources the customer would have to
# clean up manually. The Salt backend can be reconciled out-of-band.

set -u
set -o pipefail

: "${SALT_HOST:?SALT_HOST is required}"
: "${SALT_AUTH_TOKEN:?SALT_AUTH_TOKEN is required}"
: "${ATTEMPT_ID:?ATTEMPT_ID is required}"
: "${DEPLOYMENT_STATUS:?DEPLOYMENT_STATUS is required}"

SALT_HOST="${SALT_HOST%/}"
AUTH_HEADER="Bearer ${SALT_AUTH_TOKEN#Bearer }"

for cmd in jq curl; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "post_status.sh: required command not found: $cmd" >&2
        exit 0  # best-effort: don't fail apply
    }
done

payload=$(jq -n \
    --arg attemptId "$ATTEMPT_ID" \
    --arg stackId "${STACK_ID:-}" \
    --arg installationId "${INSTALLATION_ID:-}" \
    --arg accountId "${ACCOUNT_ID:-}" \
    --arg deploymentStatus "$DEPLOYMENT_STATUS" \
    --arg createdBy "IBM Schematics (manual deploy)" \
    --arg apiKey "${API_KEY:-}" \
    '{
        attemptId: $attemptId,
        stackId: $stackId,
        installationId: $installationId,
        accountId: $accountId,
        region: "global",
        createdBy: $createdBy,
        deploymentStatus: $deploymentStatus,
        connectionFields: (if $apiKey != "" then {apiKey: $apiKey} else null end)
    }')

http_code=$(curl -s -o /tmp/salt-resp.txt -w '%{http_code}' \
    --max-time 15 \
    -X POST \
    -H "Authorization: ${AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "${SALT_HOST}/v1/cloud-connect/scan/ibm" 2>/dev/null || echo "000")

if [[ "$http_code" =~ ^2 ]]; then
    echo "Salt backend: ${DEPLOYMENT_STATUS} (HTTP ${http_code})"
else
    echo "WARN: Salt backend returned HTTP ${http_code} for ${DEPLOYMENT_STATUS} (continuing)" >&2
fi

exit 0
