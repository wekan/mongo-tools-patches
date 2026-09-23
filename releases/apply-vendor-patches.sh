#!/usr/bin/env bash
# Run after go mod vendor: earlier edits to vendor/ would be overwritten.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
# Require a source root, not a subdirectory of an unrelated enclosing checkout.
[ -f go.mod ] && [ -f vendor/modules.txt ] && [ -d .git ] || {
  echo 'Run vendor patching at the upstream source repository root' >&2; exit 1;
}
[ "$(git rev-parse --show-prefix)" = '' ] || {
  echo 'Vendor patching must run at the Git repository root' >&2; exit 1;
}
for patch in "$root"/dist/vendor/*.patch; do
  [ -f "$patch" ] || { echo '::error::Telemetry removal patch is missing' >&2; exit 1; }
  (cd "$(dirname "$patch")" && sha256sum -c "$(basename "$patch" .patch).sha256sum")
  git apply --check "$patch" && git apply "$patch" || {
    echo "::error::Telemetry removal patch failed: $patch. Review the updated dependency source." >&2
    exit 1
  }
done
python3 "$root/releases/audit-telemetry.py" .
