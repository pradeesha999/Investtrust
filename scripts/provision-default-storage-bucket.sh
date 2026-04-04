#!/usr/bin/env bash
# Creates the default Firebase Storage bucket when the Firebase Console "Get Started" flow fails.
#
# Requirements:
#   - Google Cloud SDK: https://cloud.google.com/sdk/docs/install
#   - gcloud auth login (same Google account as Firebase)
#   - Billing on the GCP project (Blaze / pay-as-you-go) for default buckets created on/after Oct 30, 2024
#   - IAM: permission firebasestorage.defaultBucket.create (Project Owner/Editor usually has it)
#
# Usage:
#   ./scripts/provision-default-storage-bucket.sh [PROJECT_ID] [LOCATION]
# Example:
#   ./scripts/provision-default-storage-bucket.sh investtrust-2930a us-central1

set -euo pipefail

PROJECT_ID="${1:-investtrust-2930a}"
LOCATION="${2:-us-central1}"

if ! command -v gcloud &>/dev/null; then
  echo "Missing gcloud. Install: https://cloud.google.com/sdk/docs/install"
  exit 1
fi
if ! command -v curl &>/dev/null; then
  echo "Missing curl."
  exit 1
fi

echo "Project:  $PROJECT_ID"
echo "Location: $LOCATION (pick a Cloud Storage region: https://firebase.google.com/docs/storage/locations)"
echo ""
echo "This calls the Firebase Storage API to create/link the default bucket"
echo "(same outcome as Firebase Console → Storage → Get started)."
echo ""

TOKEN=$(gcloud auth print-access-token --project="$PROJECT_ID")

TMP=$(mktemp)
HTTP_CODE=$(curl -sS -o "$TMP" -w "%{http_code}" \
  -X POST \
  "https://firebasestorage.googleapis.com/v1alpha/projects/${PROJECT_ID}/defaultBucket" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  -d "{\"location\":\"${LOCATION}\"}" || true)

echo "HTTP status: $HTTP_CODE"
cat "$TMP"
echo ""

if [[ "$HTTP_CODE" == "400" ]] || [[ "$HTTP_CODE" == "422" ]]; then
  echo "Retrying with alternate request body..."
  HTTP_CODE=$(curl -sS -o "$TMP" -w "%{http_code}" \
    -X POST \
    "https://firebasestorage.googleapis.com/v1alpha/projects/${PROJECT_ID}/defaultBucket" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "x-goog-user-project: ${PROJECT_ID}" \
    -d "{\"defaultBucket\":{\"location\":\"${LOCATION}\"}}" || true)
  echo "HTTP status: $HTTP_CODE"
  cat "$TMP"
  echo ""
fi

rm -f "$TMP"

# 409 = already provisioned or name conflict — try deploying rules anyway
if [[ "$HTTP_CODE" == "200" ]] || [[ "$HTTP_CODE" == "201" ]] || [[ "$HTTP_CODE" == "409" ]]; then
  echo ""
  echo "Done (HTTP $HTTP_CODE). Deploy rules with:"
  echo "  npm run firebase:deploy:storage"
  exit 0
fi

echo ""
echo "Troubleshooting:"
echo "  • 403 / PERMISSION_DENIED: sign in with an account that owns the project (gcloud auth login)."
echo "  • FAILED_PRECONDITION / billing: enable Blaze in Firebase → Project settings → Usage and billing."
echo "  • API not enabled: gcloud services enable firebasestorage.googleapis.com --project=$PROJECT_ID"
echo "  • Wrong region: try us-central1, europe-west1, or asia-southeast1."
exit 1
