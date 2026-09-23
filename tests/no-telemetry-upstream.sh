#!/usr/bin/env bash
# Audit an existing, patched, dependency-refreshed tree, or prepare current upstream.
# Network failures while cloning are a skip (77); audit failures never are.
set -euo pipefail
export GOTELEMETRY=off
root="$(cd "$(dirname "$0")/.." && pwd)"
if [ "${1:-}" = --source ]; then
  exec python3 "$root/releases/audit-telemetry.py" "${2:?source directory required}"
fi
ref="$(bash "$root/releases/newest-release.sh" "$root" "${1:-}")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
if ! git clone --quiet --depth 1 --single-branch --branch "$ref" \
    https://github.com/mongodb/mongo-tools.git "$work/source"; then
  echo 'SKIP: could not clone upstream mongo-tools.'
  exit 77
fi
cd "$work/source"
for patch in "$root"/dist/all/*.patch; do
  [ -f "$patch" ] || continue
  (cd "$(dirname "$patch")" && sha256sum -c "$(basename "$patch" .patch).sha256sum")
  git apply --check "$patch"
  git apply "$patch"
done
bash "$root/releases/update-dependencies.sh"
