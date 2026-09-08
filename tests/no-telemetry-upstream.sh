#!/usr/bin/env bash
# This repo's README says mongo-tools has no telemetry/phone-home mechanism of
# its own to remove - unlike wekan/mongosh-patches and this fork's FerretDB,
# which both patch one out. That claim was checked once by hand against
# upstream source; this test re-checks it against the CURRENT upstream ref, so
# a future mongo-tools release that adds a beacon/analytics client is caught
# here instead of being silently missed.
#
#   ./tests/no-telemetry-upstream.sh          # current upstream master
#   ./tests/no-telemetry-upstream.sh 100.18.0 # a particular tag
#
# Needs the network. Exits 77 (the conventional "skipped") when upstream
# cannot be reached, matching tests/patches-apply.sh.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fails=0
ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }

command -v git >/dev/null || { echo "git is required."; exit 1; }

V="$(bash "$ROOT/releases/newest-release.sh" "$ROOT" "${1:-}" 2>/dev/null)"
if [ -z "${V:-}" ]; then
  echo "SKIP: could not resolve the upstream ref."
  exit 77
fi
echo "Upstream ref: $V"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
if ! git clone --quiet --depth 1 --single-branch --branch "$V" \
    https://github.com/mongodb/mongo-tools.git "$TMP/toolssrc" 2>/dev/null; then
  echo "SKIP: could not clone upstream mongo-tools."
  exit 77
fi
cd "$TMP/toolssrc" || exit 1

# 1. mongo-tools' OWN code (everything outside vendor/) must not match any of
# the words a phone-home mechanism would use. This is the actual claim: no
# analytics client, no beacon, no usage-data upload, anywhere in the tools'
# own source - not just at the one place upstream currently doesn't have one.
pattern='telemetry|analytics|phone.?home|beacon|do_not_track|usage.?data|segment\.io|mixpanel'
own_hits="$(grep -rniIE "$pattern" --include='*.go' . 2>/dev/null | grep -v '^\./vendor/' || true)"
if [ -z "$own_hits" ]; then
  ok "no telemetry/analytics/beacon/phone-home code in mongo-tools' own source"
else
  fail "mongo-tools' own source now matches a telemetry pattern - update the README and patch it out:"
  printf '%s\n' "$own_hits" | sed 's/^/    /'
fi

# 2. The vendored Azure SDK's telemetryPolicy is the one known match, and it
# is a User-Agent string builder for Azure Key Vault/KMS HTTP calls, not a
# data collector. Confirm it still IS that (it sets a User-Agent header and
# does nothing else network-related) rather than assuming the shape found
# once stays true forever.
azure_telemetry="vendor/github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime/policy_telemetry.go"
if [ -f "$azure_telemetry" ]; then
  if grep -q 'HeaderUserAgent' "$azure_telemetry" && ! grep -qiE 'http\.(Post|Get)\(|NewRequest\(' "$azure_telemetry"; then
    ok "the one vendored telemetry hit is still just a User-Agent header, not a network call"
  else
    fail "$azure_telemetry no longer looks like a plain User-Agent builder - re-check what it does"
  fi
else
  ok "the vendored Azure telemetry policy file is gone entirely (nothing to re-check)"
fi

# 3. No tool defines its own --telemetry or DO_NOT_TRACK flag - confirming
# there is no opt-out UI to translate into a fork notice, because there is no
# opt-in to begin with.
flag_hits="$(grep -rniIE '"telemetry"|"do_not_track"|DO_NOT_TRACK' --include='*.go' . 2>/dev/null | grep -v '^\./vendor/' || true)"
if [ -z "$flag_hits" ]; then
  ok "no --telemetry or DO_NOT_TRACK flag defined by mongo-tools itself"
else
  fail "mongo-tools now defines a telemetry-related flag - update the README and patch it out:"
  printf '%s\n' "$flag_hits" | sed 's/^/    /'
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "no-telemetry-upstream: mongo-tools $V still has nothing to remove."
else
  echo "no-telemetry-upstream: $fails check(s) failed - see above."
fi
exit "$fails"
