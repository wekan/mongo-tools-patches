#!/bin/sh
#
# release-assets.sh <tag> - print the names of the assets a release already has,
# one per line. Prints nothing (and succeeds) when the release does not exist,
# because "no release" and "a release with nothing on it" mean the same thing to
# a caller asking what is still missing.
#
# This is the whole of what release-all-missing.yml needs to know: everything it
# does is "build the things whose names are NOT in this list". Kept as a script
# rather than inline YAML so both workflows read the release the same way and
# `sh -n` can check it.
#
# Needs gh and GH_TOKEN in the environment - and GH_REPO, which gh reads
# natively to know WHICH repository to ask. That is not optional here: gh
# otherwise works the repository out from the git remote of the working
# directory, and by the time this runs the working directory is the UPSTREAM
# mongo-tools clone. Asking it for a release answers about mongodb/mongo-tools.

set -eu

tag="${1:?usage: release-assets.sh <tag>}"

if gh release view "$tag" >/dev/null 2>&1; then
    # --jq over the API's asset list: `gh release view --json assets` gives an
    # array of objects and only the name matters here.
    gh release view "$tag" --json assets --jq '.assets[].name'
else
    echo "release-assets.sh: no release $tag yet - everything is missing." >&2
fi
