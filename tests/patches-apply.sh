#!/usr/bin/env bash
# Do the patches still apply to the upstream ref the build would clone? That
# is the question this repo lives or dies on: a patch that no longer applies
# fails the build minutes in, and the only warning is a `git apply` error in a
# log nobody is watching.
#
#   ./tests/patches-apply.sh              # current upstream master
#   ./tests/patches-apply.sh 100.18.0     # a particular tag
#
# It does NOT clone mongo-tools - that is a large Go repository with its whole
# vendor/ tree, to answer a question about a handful of files. It reconstructs a
# tree of exactly the files the patches touch, fetched from mongodb/mongo-tools
# at the tag, and runs `git apply` over it the way releases/apply-patches.sh
# does: checksum first, then the patches in name order, cumulatively, so a
# conflict between two patches of this repo's own is caught as well as one
# against upstream.
#
# Needs the network. Exits 77 (the conventional "skipped") when upstream cannot
# be reached, so a sandbox without network says so rather than reporting a green
# run it did not do.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RAW="https://raw.githubusercontent.com/mongodb/mongo-tools"

fails=0
ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }

command -v git  >/dev/null || { echo "git is required.";  exit 1; }
command -v curl >/dev/null || { echo "curl is required."; exit 1; }

# The version the build itself would use, resolved by the build's own script, so
# this test and the build never disagree about what "newest" is.
V="$(bash "$ROOT/releases/newest-release.sh" "$ROOT" "${1:-}" 2>/dev/null)"
if [ -z "${V:-}" ]; then
  echo "SKIP: could not resolve the upstream ref."
  exit 77
fi
echo "Upstream ref: $V"

shopt -s nullglob
patches=( "$ROOT"/dist/all/*.patch )
if [ "${#patches[@]}" -eq 0 ]; then
  # Not a skip and not a failure: there are no patches today (see
  # dist/README.md), and the thing this test could still get wrong - resolving
  # the upstream release - has just been checked above.
  echo "No patches in dist/all - upstream $V is built as it is. Nothing to apply."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1
git init -q .

# Which files the patches touch, straight out of their own headers. Derived
# rather than listed, so a patch that starts touching another file is fetched
# without anyone remembering to add it here. `/dev/null` is the a-side of a
# patch that CREATES a file - there is nothing upstream to fetch for it.
files="$(cat "${patches[@]}" | sed -n 's#^--- a/##p' | sort -u | grep -v '^/dev/null$')"
[ -n "$files" ] || { echo "The patches touch no existing upstream file."; exit 1; }

echo "Fetching the $(printf '%s\n' "$files" | wc -l | tr -d ' ') file(s) the patches touch, at $V:"
for f in $files; do
  mkdir -p "$(dirname "$f")"
  if ! curl -fsSL --retry 3 --retry-delay 2 -o "$f" "$RAW/$V/$f"; then
    if [ ! -s "$f" ] && ! curl -fsS --max-time 20 -o /dev/null "$RAW/$V/README.md" 2>/dev/null; then
      echo "SKIP: github.com is unreachable."
      exit 77
    fi
    fail "upstream $V has no $f - the patch is against a file that is gone"
    rm -f "$f"
  fi
done
git add -A
git -c user.email=t@t -c user.name=t commit -qm "upstream $V"
echo

for p in "${patches[@]}"; do
  n="$(basename "$p")"
  # The checksum first, from inside the section directory - the same check, in
  # the same place, the build makes before it applies anything.
  if ! ( cd "$ROOT/dist/all" && sha256sum -c "${n%.patch}.sha256sum" >/dev/null 2>&1 ); then
    fail "all/$n: checksum does not match the patch"
    continue
  fi
  if err="$(git apply --whitespace=nowarn "$p" 2>&1)"; then
    ok "all/$n"
  else
    fail "all/$n does not apply to $V: $(printf '%s' "$err" | head -3 | tr '\n' ' ')"
  fi
done

echo
if [ "$fails" -eq 0 ]; then
  echo "patches-apply: every patch applies to $V."
else
  echo "patches-apply: $fails failure(s) against $V."
fi
exit $(( fails > 0 ))
