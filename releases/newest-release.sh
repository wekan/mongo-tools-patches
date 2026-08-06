#!/usr/bin/env bash
# Print the upstream MongoDB Database Tools release to build: the NEWEST
# published release tag <MAJOR>.<MINOR>.<PATCH> at mongodb/mongo-tools, where
# <MAJOR> is read from tools-major.txt. "Release" means a published tag - never a
# branch head, never a commit between releases - so a build is always of an
# upstream release and is reproducible.
#
# Upstream tags carry NO leading v: the Database Tools are tagged `100.17.0`,
# not `v100.17.0`. That is the one difference from wekan/node-patches' script of
# the same name, and it is why this one exists rather than being shared.
#
# Usage:  newest-release.sh <repo-root> [version-override]
#
# A non-empty version-override (second argument) is printed verbatim instead of
# querying upstream. That is how a workflow hands the build the version its plan
# already resolved, so a full run and a fill-in run agree.
#
# UPSTREAM_URL overrides where upstream is read from. It is here for the tests,
# which point it at a local fixture repository so they can run without network.
set -euo pipefail

ROOT="${1:-.}"
OVERRIDE="${2:-}"
UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/mongodb/mongo-tools.git}"

if [ -n "$OVERRIDE" ]; then
  printf '%s\n' "$OVERRIDE"
  exit 0
fi

MAJOR="$(tr -cd '0-9' < "$ROOT/tools-major.txt")"
[ -n "$MAJOR" ] || { echo "::error::$ROOT/tools-major.txt has no major version number." >&2; exit 1; }

# Release tags only: --refs drops the ^{} dereference lines, and the strict grep
# drops anything that is not MAJOR.MINOR.PATCH (no -rc, no r4.2.x, no other
# major line - upstream's tag list still carries the old r-prefixed ones).
VERSION="$(git ls-remote --tags --refs "$UPSTREAM_URL" "${MAJOR}.*" \
  | awk '{print $2}' | sed 's#refs/tags/##' \
  | grep -E "^${MAJOR}\.[0-9]+\.[0-9]+$" | sort -V | tail -1)"
[ -n "$VERSION" ] || { echo "::error::Found no upstream ${MAJOR}.x release tag at ${UPSTREAM_URL}." >&2; exit 1; }

printf '%s\n' "$VERSION"
