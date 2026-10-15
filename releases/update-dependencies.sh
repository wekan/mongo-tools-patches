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
# Upstream master moves on: when it imports a module (or a new major version
# such as golang-set/v3) that the reviewed graph does not list, the readonly
# vendor step fails. Say what to do instead of leaving only Go's "go get" hint,
# which a release must never follow.
if ! GOFLAGS=-mod=readonly go mod vendor; then
  echo "::error::Upstream $(git rev-parse --short HEAD 2>/dev/null || echo source) needs modules missing from releases/reviewed-go. Refresh releases/reviewed-go/go.mod and go.sum from that upstream go.mod/go.sum (keeping the reviewed go directive), then update releases/telemetry-audit.json." >&2
  exit 1
fi

bash "$(dirname "$0")/apply-vendor-patches.sh"
bash "$(dirname "$0")/../tests/sdk-telemetry.sh" "$PWD"
