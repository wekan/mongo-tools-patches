#!/usr/bin/env bash
# Print the upstream MongoDB Database Tools ref to build. The default is the
# current upstream master branch, including changes not yet in a release.
#
# Usage:  newest-release.sh <repo-root> [version-override]
#
# A non-empty override is printed verbatim, allowing an older tag or another
# branch to be reproduced deliberately.
#
# UPSTREAM_URL overrides where upstream is read from. It is here for the tests,
# which point it at a local fixture repository so they can run without network.
set -euo pipefail

_ROOT="${1:-.}"
OVERRIDE="${2:-}"

if [ -n "$OVERRIDE" ]; then
  printf '%s\n' "$OVERRIDE"
  exit 0
fi

printf '%s\n' master
