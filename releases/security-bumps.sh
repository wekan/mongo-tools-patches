#!/usr/bin/env bash
# Raise the Go toolchain and the VENDORED dependencies of the upstream tree the
# patches were just applied to.
#
#   security-bumps.sh toolchain     # before setup-go: rewrites go.mod's `go` line
#   security-bumps.sh vendor        # after setup-go: go get + tidy + vendor
#
# Why this exists. The nine binaries this repository publishes - bsondump,
# mongodump, mongoexport, mongofiles, mongoimport, mongorestore, mongostat,
# mongotop - are scanned as part of the WeKan image, and what a scanner reads out
# of a Go binary is the toolchain that built it plus the module versions baked
# into it. Every one of them reported the same 37 findings, because they are the
# same build:
#
#   stdlib          1.25.9   the Go release upstream's go.mod asked for
#   x/crypto        0.45.0   vendored by upstream
#   x/net           0.47.0   vendored by upstream
#   x/text          0.31.0   vendored by upstream
#   x/sys           0.38.0   vendored by upstream
#
# None of that is upstream being careless - a release is vendored at the moment
# it is cut and the advisories arrive afterwards. But WeKan ships those binaries,
# so WeKan is where they get raised, and a patch file cannot do it: `vendor/` is
# thousands of files and a .patch against it would not apply to the next upstream
# release. A script re-resolves instead, so it keeps working as upstream moves.
#
# The versions are in releases/security-minimums.txt, one `module version` per
# line, and a module is only raised when what upstream vendored is BELOW it.
set -euo pipefail

MODE="${1:?usage: security-bumps.sh toolchain|vendor}"
HERE="$(cd "$(dirname "$0")" && pwd)"
MINIMUMS="$HERE/security-minimums.txt"

# The toolchain minimum lives in the same file, as the pseudo-module `go`.
go_minimum() { awk '$1 == "go" { print $2 }' "$MINIMUMS"; }

# "1.25.9" is older than "1.25.12" - compare the parts as NUMBERS. sort -V would
# do it too, but not on every busybox this may run in.
version_lt() {
    local a b i
    IFS=. read -r -a a <<< "${1#v}"
    IFS=. read -r -a b <<< "${2#v}"
    for i in 0 1 2; do
        local x="${a[i]:-0}" y="${b[i]:-0}"
        x="${x%%-*}"; y="${y%%-*}"
        (( x < y )) && return 0
        (( x > y )) && return 1
    done
    return 1
}

case "$MODE" in
toolchain)
    # Runs BEFORE actions/setup-go, which reads this line to decide which Go it
    # installs. Rewriting it here is what gets the fixed stdlib into the binary;
    # doing it afterwards would bump the file and build with the old toolchain.
    MIN="$(go_minimum)"
    CURRENT="$(awk '/^go [0-9]/ { print $2; exit }' go.mod)"
    if [ -z "$CURRENT" ]; then
        echo "security-bumps.sh: no 'go' directive in go.mod - is this an upstream tree?" >&2
        exit 1
    fi
    if version_lt "$CURRENT" "$MIN"; then
        sed -i.bak "0,/^go [0-9].*/s//go ${MIN}/" go.mod && rm -f go.mod.bak
        echo "Go toolchain ${CURRENT} -> ${MIN} (go.mod)."
    else
        echo "Go toolchain ${CURRENT} is already at or above ${MIN}."
    fi
    ;;
vendor)
    # Runs AFTER setup-go, because every command here is a go command.
    #
    # `go get` each module that is below its minimum, then tidy, then re-vendor.
    # -mod=mod because the tree is vendored: without it every go command insists
    # on using vendor/ as it is and refuses to change the requirements.
    export GOFLAGS="${GOFLAGS:-} -mod=mod"
    raised=()
    while read -r module minimum; do
        case "$module" in ''|'#'*|go) continue ;; esac
        current="$(go list -m -f '{{.Version}}' "$module" 2>/dev/null || true)"
        if [ -z "$current" ]; then
            echo "  ${module} is not in this release's module graph - skipped."
            continue
        fi
        if version_lt "${current#v}" "${minimum#v}"; then
            echo "  ${module} ${current} -> ${minimum}"
            raised+=("${module}@${minimum}")
        else
            echo "  ${module} ${current} is already at or above ${minimum}."
        fi
    done < "$MINIMUMS"

    if [ ${#raised[@]} -eq 0 ]; then
        echo "Nothing to raise; upstream vendored everything at or above the minimums."
        exit 0
    fi

    go get "${raised[@]}"
    go mod tidy
    go mod vendor
    echo "Raised ${#raised[@]} module(s) and re-vendored."
    ;;
*)
    echo "security-bumps.sh: unknown mode '$MODE' (toolchain|vendor)" >&2
    exit 1
    ;;
esac
