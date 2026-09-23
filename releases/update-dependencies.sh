#!/usr/bin/env bash
# Restore the reviewed upstream module graph and regenerate vendor/.
# Keep the compatibility filename used by both release workflows.
set -euo pipefail
export GOTELEMETRY=off

root="$(cd "$(dirname "$0")/.." && pwd)"
# Release builds use the reviewed graph. Updating dependencies is a separate
# review task: never resolve new versions after the local release preflight.
cp "$root/releases/reviewed-go/go.mod" go.mod
cp "$root/releases/reviewed-go/go.sum" go.sum
GOFLAGS=-mod=readonly go mod vendor

bash "$(dirname "$0")/apply-vendor-patches.sh"
bash "$(dirname "$0")/../tests/sdk-telemetry.sh" "$PWD"
