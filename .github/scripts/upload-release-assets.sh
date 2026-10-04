#!/usr/bin/env bash
#
# upload-release-assets.sh <tag> <file>... - attach files to an EXISTING GitHub
# Release, replacing assets of the same name (--clobber), with retries.
#
# build-tools.sh calls this (as MONGO_TOOLS_PUBLISH) once per binary, right
# after that binary compiled, passed the telemetry audit and had its .sha256sum
# written - so it is on the release while the others are still compiling.
# attach-finished.sh calls it for any finished binary whose upload a cancel or
# a failure cut short. The release must already exist; the workflows create it
# (empty) before the build.
#
# One failed asset must not throw away a run that took hours to compile, so an
# attempt that fails is retried - and only with the files the release does NOT
# yet carry at the right size. --clobber keeps every attempt idempotent: the
# first one replaces a previous run's copies, a later one replaces whatever a
# broken upload left behind.
#
# Every binary's .sha256sum is a file in the list like any other, so a binary
# and its checksum arrive together. There is no combined checksum file in this
# repo to rebuild.
#
# Needs gh, GH_TOKEN, and GH_REPO (see release-assets.sh for why GH_REPO is not
# optional here). Tunable for tests: UPLOAD_ATTEMPTS (default 5) and
# UPLOAD_RETRY_DELAY (seconds, default 15, doubled after each failure).

set -euo pipefail

tag="${1:?usage: upload-release-assets.sh <tag> <file>...}"
shift
[ "$#" -gt 0 ] || { echo "::error::upload-release-assets.sh: no files to upload to $tag" >&2; exit 1; }

attempts="${UPLOAD_ATTEMPTS:-5}"
delay="${UPLOAD_RETRY_DELAY:-15}"

for f in "$@"; do
  [ -f "$f" ] || { echo "::error::upload-release-assets.sh: $f is not a file" >&2; exit 1; }
done

pending=( "$@" )
attempt=1
while :; do
  echo "Uploading ${#pending[@]} file(s) to $tag (attempt $attempt of $attempts)."
  if gh release upload "$tag" "${pending[@]}" --clobber; then
    echo "All $# file(s) are on $tag."
    exit 0
  fi
  if [ "$attempt" -ge "$attempts" ]; then
    echo "::error::Uploading to $tag failed $attempts time(s); still missing: ${pending[*]##*/}" >&2
    exit 1
  fi

  # Keep only what is not on the release yet, at the size it has here. A name
  # that is there with the wrong size is a broken upload and is sent again.
  have="$(gh release view "$tag" --json assets \
            --jq '.assets[] | "\(.name)\t\(.size)"' 2>/dev/null || true)"
  next=()
  for f in "${pending[@]}"; do
    size="$(wc -c < "$f" | tr -d ' ')"
    printf '%s\n' "$have" | grep -qxF "$(basename "$f")	$size" || next+=( "$f" )
  done
  if [ "${#next[@]}" -eq 0 ]; then
    echo "gh reported a failure, but every file is on $tag at the right size."
    exit 0
  fi
  pending=( "${next[@]}" )

  echo "::warning::Upload to $tag failed; retrying ${#pending[@]} file(s) in ${delay}s."
  sleep "$delay"
  delay=$(( delay * 2 ))
  attempt=$(( attempt + 1 ))
done
