#!/usr/bin/env bash
#
# Post a deployment status to the Salt Security Cloud Connect backend.
# Invoked from null_resource.local-exec provisioners in main.tf, once before
# any IAM is created (Initiated) and once after the API key is issued
# (Succeeded). Called for every apply — there is no opt-out.
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
# Fails the apply on non-2xx. The module only creates a handful of IAM
# resources, so the cost of aborting on a transient backend blip is low
# (retry is cheap), and it prevents the worse outcome: IAM resources
# existing without the Salt backend knowing about them.

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
        exit 1
    }
done

RESP_FILE=$(mktemp -t salt-resp.XXXXXX)
trap 'rm -f "$RESP_FILE"' EXIT

# connectionFields must always be a populated object — the backend's
# unified-scan validator returns 400 "ConnectionFields is required" if
# the key is null or missing. On Initiated we don't have the api_key
# yet, so we send an empty-string placeholder (same pattern the Azure
# script uses for clientId/tenantId/clientSecret on its Initiated POST).
payload=$(jq -n \
    --arg attemptId "$ATTEMPT_ID" \
    --arg stackId "${STACK_ID:-}" \
    --arg installationId "${INSTALLATION_ID:-}" \
    --arg accountId "${ACCOUNT_ID:-}" \
    --arg deploymentStatus "$DEPLOYMENT_STATUS" \
    --arg errorMessage "${ERROR_MESSAGE:-}" \
    --arg createdBy "IBM Cloud Schematics" \
    --arg apiKey "${API_KEY:-}" \
    '{
        attemptId: $attemptId,
        stackId: $stackId,
        installationId: $installationId,
        accountId: $accountId,
        region: "global",
        createdBy: $createdBy,
        deploymentStatus: $deploymentStatus,
        errorMessage: $errorMessage,
        connectionFields: {apiKey: $apiKey}
    }')

http_code=$(curl -s -o "$RESP_FILE" -w '%{http_code}' \
    --max-time 15 \
    -X POST \
    -H "Authorization: ${AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "${SALT_HOST}/v1/cloud-connect/scan/ibm" 2>/dev/null || echo "000")

if [[ "$http_code" =~ ^2 ]]; then
    echo "Salt backend: ${DEPLOYMENT_STATUS} (HTTP ${http_code})"
    exit 0
fi

echo "ERROR: Salt backend returned HTTP ${http_code} for ${DEPLOYMENT_STATUS}" >&2
if [ -s "$RESP_FILE" ]; then
    echo "Response: $(head -c 500 "$RESP_FILE")" >&2
fi
exit 1