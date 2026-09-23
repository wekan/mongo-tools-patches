#!/usr/bin/env bash
# Run against a prepared upstream tree. All HTTP requests use in-process fakes.
set -euo pipefail
export GOTELEMETRY=off
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "${1:?prepared upstream source directory required}"
created=()
trap 'for file in "${created[@]}"; do rm -f "$file"; done' EXIT
packages=()
while read -r fixture package; do
  file="vendor/$package/wekan_telemetry_test.go"
  [ ! -e "$file" ] || { echo "Refusing to overwrite $file" >&2; exit 1; }
  cp "$root/tests/sdk-telemetry/$fixture.go" "$file"
  created+=("$file")
  packages+=("./vendor/$package")
done <<'PACKAGES'
azure github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime
aws-v2 github.com/aws/aws-sdk-go-v2/aws/middleware
aws-v1 github.com/aws/aws-sdk-go/aws/corehandlers
msal github.com/AzureAD/microsoft-authentication-library-for-go/apps/internal/oauth/ops/internal/comm
msal-managed github.com/AzureAD/microsoft-authentication-library-for-go/apps/managedidentity
PACKAGES
CGO_ENABLED=0 go test -mod=vendor -count=1 "${packages[@]}"
