#!/bin/bash
#
# build-tools.sh - cross-compile every MongoDB Database Tool for every platform
# into out/, with a .sha256sum beside each binary.
#
# ONE copy of the build, used by both release-all.yml (build everything) and
# release-all-missing.yml (build only what the release does not already have).
# The target list and the ldflags live here so the two workflows cannot drift
# apart - which they would, because the interesting part of "build the missing
# ones" is exactly the list that "build all of them" also needs.
#
# It runs in the tree releases/apply-patches.sh leaves behind: upstream
# mongodb/mongo-tools at an exact commit, with this repo's patches applied. It came
# from the wekan/mongo-tools fork unchanged in substance when that fork was
# retired in favour of this repo; what changed is where it writes (out/, because
# dist/ here is the patch sections) and which commit it stamps (the UPSTREAM
# commit, not this repo's - the source a binary was built from is upstream's).
#
# Environment:
#   TOOLS_VER    version string stamped into each binary   (required)
#   TOOLS_COMMIT upstream commit stamped into each binary  (optional)
#   SKIP_LIST    path to a file of asset names, one per line: any binary whose
#                own name AND whose .sha256sum are both in that list is not
#                rebuilt. Absent or empty => build everything.
#   OUT          output directory (default: out)
#
# Because the tools are pure Go (CGO disabled), every architecture is buildable
# here, including ones MongoDB ships no prebuilt tools for (riscv64, loong64). A
# target that does not compile is skipped and reported, never fatal - so the
# caller must NOT treat a missing binary as a build failure, only as a binary
# this platform does not have. A tool that stops compiling for a platform is
# also the moment a patch in dist/ becomes worth writing.

set -uo pipefail

out="${OUT:-out}"
tools_ver="${TOOLS_VER:?TOOLS_VER is required}"
tools_commit="${TOOLS_COMMIT:-${GITHUB_SHA:-unknown}}"
skip_list="${SKIP_LIST:-}"
tmp_root="${TMPDIR:-$PWD/.tools/tmp}"

mkdir -p "$out" "$tmp_root"

TOOLS="bsondump mongodump mongoexport mongofiles mongoimport mongorestore mongostat mongotop"
# name  goos  goarch  goarm   ('-' = no GOARM). Same arch tokens + set as
# wekan/FerretDB's build.sh so ferretdb-<arch> and mongodump-<arch> match.
#
# armv6 is GOARM=6, hard-float VFPv2 - Raspberry Pi 1 and Zero. armel below is
# GOARM=5 and WOULD run on those boards, in software floating point, so it is
# not a substitute for them; it stays for genuine ARMv5.
TARGETS="
  amd64 linux amd64 -
  arm64 linux arm64 -
  armhf linux arm 7
  armv6 linux arm 6
  armel linux arm 5
  i386 linux 386 -
  ppc64le linux ppc64le -
  s390x linux s390x -
  riscv64 linux riscv64 -
  loong64 linux loong64 -
  win64 windows amd64 -
  win-arm64 windows arm64 -
  win32 windows 386 -
  mac-amd64 darwin amd64 -
  mac-arm64 darwin arm64 -
  freebsd-amd64 freebsd amd64 -
  freebsd-i386 freebsd 386 -
  freebsd-armel freebsd arm 5
  freebsd-armv6 freebsd arm 6
  freebsd-armv7 freebsd arm 7
  freebsd-arm64 freebsd arm64 -
  aix-ppc64 aix ppc64 -
  dragonfly-amd64 dragonfly amd64 -
  mips linux mips -
  mipsle linux mipsle -
  mips64 linux mips64 -
  mips64le linux mips64le -
  ppc64 linux ppc64 -
  netbsd-i386 netbsd 386 -
  netbsd-amd64 netbsd amd64 -
  netbsd-armel netbsd arm 5
  netbsd-armv6 netbsd arm 6
  netbsd-armv7 netbsd arm 7
  netbsd-arm64 netbsd arm64 -
  openbsd-i386 openbsd 386 -
  openbsd-amd64 openbsd amd64 -
  openbsd-armel openbsd arm 5
  openbsd-armv6 openbsd arm 6
  openbsd-armv7 openbsd arm 7
  openbsd-arm64 openbsd arm64 -
  openbsd-ppc64 openbsd ppc64 -
  openbsd-riscv64 openbsd riscv64 -
  android-arm64 android arm64 -
"

# Is this asset already on the release? BOTH the binary and its checksum have to
# be there: a release carrying a binary whose .sha256sum upload failed is exactly
# the half-published state this workflow exists to repair, and treating the
# binary alone as "present" would leave it that way forever.
already_there() {
    [ -n "$skip_list" ] && [ -s "$skip_list" ] || return 1
    grep -qxF "$1" "$skip_list" && grep -qxF "$1.sha256sum" "$skip_list"
}

# No ssl/sasl tags and no -buildmode=pie: keep the build CGO-free so it
# cross-compiles to every GOARCH (those pull in C libs / a cross toolchain).
LDFLAGS="-s -w -X main.VersionStr=$tools_ver -X main.GitCommit=$tools_commit"

built=0
skipped_existing=0
skipped_broken=0

while read -r name goos goarch goarm; do
    [ -n "${name:-}" ] || continue
    arm=""; [ "$goarm" != "-" ] && arm="$goarm"
    ext=""; [ "$goos" = windows ] && ext=".exe"
    for tool in $TOOLS; do
        asset="${tool}-${name}${ext}"
        if already_there "$asset"; then
            echo "  have    $asset"
            skipped_existing=$((skipped_existing + 1))
            continue
        fi
        if CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" GOARM="$arm" \
             go build -trimpath -ldflags "$LDFLAGS" \
             -o "$out/$asset" "./${tool}/main" 2>"$tmp_root/${tool}-${name}.log"; then
            echo "  built   $asset"
            built=$((built + 1))
        else
            echo "  skipped $asset (does not compile)"
            tail -2 "$tmp_root/${tool}-${name}.log" | sed 's/^/          /' || true
            skipped_broken=$((skipped_broken + 1))
        fi
    done
done <<EOF
$TARGETS
EOF

echo "=== built $built, already on the release $skipped_existing, does not compile $skipped_broken ==="
echo "=== $out ==="
ls -1 "$out" 2>/dev/null || true

# A checksum beside every binary, in the "<sum>  <file>" format sha256sum -c
# reads, so a consumer can tell a truncated or tampered download from a good
# one. One file per binary, not one list for the release: this release carries
# eight tools times a dozen platforms, and a consumer fetching one of them
# should not have to pull a list of ninety-six to check it.
(
    cd "$out" || exit 0
    for f in *; do
        [ -e "$f" ] || continue
        case "$f" in *.sha256sum) continue ;; esac
        sha256sum "$f" > "${f}.sha256sum"
    done
)

# Nothing built AND nothing skipped-as-existing is a real failure: it means the
# toolchain is broken rather than the release being complete.
if [ "$built" -eq 0 ] && [ "$skipped_existing" -eq 0 ]; then
    echo "::error::no binaries were built and none were already on the release"
    exit 1
fi
