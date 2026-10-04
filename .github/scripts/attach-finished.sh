#!/usr/bin/env bash
#
# attach-finished.sh <tag> [--check]
#
# Make sure every binary build-tools.sh FINISHED in this run is on the release,
# together with its .sha256sum.
#
# Normally build-tools.sh attached each binary the moment it was finished
# (MONGO_TOOLS_PUBLISH), and this finds nothing to do. It is for the run that
# was CANCELLED or failed part way: the workflows run it with always(), so a
# binary that finished but whose upload was cut short is still attached rather
# than lost with the run.
#
# "Finished" means listed in FINISHED_LIST (default .tools/finished.list), which
# build-tools.sh writes only after a binary compiled, passed the telemetry audit
# and had its .sha256sum written. A file in out/ that is NOT listed - a compile
# the cancel interrupted, or one whose audit had not completed - is never
# attached, whatever it looks like.
#
# --check   attach nothing; list what is missing and exit 1 if anything is.
#
# Needs gh, GH_TOKEN and GH_REPO (see release-assets.sh). Uploads go through
# upload-release-assets.sh, with its retries.

set -euo pipefail

tag="${1:?usage: attach-finished.sh <tag> [--check]}"
check=0
[ "${2:-}" != --check ] || check=1
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
finished="${FINISHED_LIST:-.tools/finished.list}"
out="${OUT:-out}"

if [ ! -s "$finished" ]; then
  echo "No binary finished building in this run; nothing to attach."
  exit 0
fi

have="$(gh release view "$tag" --json assets --jq '.assets[] | "\(.name)\t\(.size)"')"
on_release() {   # <file> -> the release has it, at this size
  printf '%s\n' "$have" | grep -qxF "$(basename "$1")	$(wc -c < "$1" | tr -d ' ')"
}

missing=()
n=0
while IFS= read -r asset; do
  [ -n "$asset" ] || continue
  n=$((n + 1))
  for f in "$out/$asset" "$out/$asset.sha256sum"; do
    if [ ! -f "$f" ]; then
      echo "::error::$asset is listed as finished but $f does not exist." >&2
      exit 1
    fi
    on_release "$f" || missing+=( "$f" )
  done
done < "$finished"

if [ "${#missing[@]}" -eq 0 ]; then
  echo "All $n finished binaries and their checksums are on $tag."
  exit 0
fi

if [ "$check" -eq 1 ]; then
  echo "::error::Finished but not on $tag: ${missing[*]##*/}" >&2
  exit 1
fi

echo "Attaching ${#missing[@]} finished file(s) that are not on $tag yet."
bash "$here/upload-release-assets.sh" "$tag" "${missing[@]}"
