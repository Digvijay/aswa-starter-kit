#!/usr/bin/env bash
# Build + deploy the chosen backend (BACKEND_LANGUAGE) to the Function App
# provisioned by Bicep. Used as the `postprovision` hook so `azd up` does the
# right thing for all three runtimes — including .NET on Flex Consumption,
# which azd 1.24's built-in deploy can't handle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LANG_VAL="${BACKEND_LANGUAGE:-node}"

echo "deploy-api: building backend ($LANG_VAL)"
"$ROOT/scripts/build-api.sh"

# Function App was tagged in Bicep so we can find it without a hard-coded name.
RG="$(azd env get-value AZURE_RESOURCE_GROUP 2>/dev/null || true)"
if [ -z "$RG" ]; then
  ENV_NAME="$(azd env get-value AZURE_ENV_NAME)"
  RG="rg-$ENV_NAME"
fi
APP="$(azd env get-value SERVICE_API_NAME 2>/dev/null || true)"
if [ -z "$APP" ]; then
  APP="$(az functionapp list -g "$RG" --query "[0].name" -o tsv)"
fi

echo "deploy-api: target = $RG / $APP"

ZIP="$(mktemp -d)/api.zip"
( cd "$ROOT/src/api" && zip -r -q "$ZIP" . )

echo "deploy-api: uploading $(wc -c <"$ZIP") bytes"
az functionapp deployment source config-zip \
  --resource-group "$RG" \
  --name "$APP" \
  --src "$ZIP" \
  --build-remote false \
  --only-show-errors

echo "deploy-api: done"
