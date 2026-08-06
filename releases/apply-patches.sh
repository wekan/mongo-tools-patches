#!/usr/bin/env bash
# Clone the upstream MongoDB Database Tools at a release tag into the CURRENT
# directory and apply this repo's patches on top, so what is left is an ordinary
# mongo-tools source tree the build can compile.
#
#   apply-patches.sh <patches-root> [version-override]
#
#   patches-root      where THIS repository is checked out (the workflows use
#                     _patches, so the upstream tree can be moved to the
#                     workspace root beside it)
#   version-override  build this exact upstream release instead of the newest
#                     <MAJOR>.x one (tools-major.txt)
#
# It is a script, not a block of YAML, for the same reason the build is a script:
# release-all.yml and release-all-missing.yml both need it, and two copies of
# "clone upstream and apply the patches" would drift - after which a binary
# added to a release later would be built from a different source than the ones
# beside it.
#
# Prints, and when running under Actions also records:
#   VERSION           the upstream release that was cloned
#   UPSTREAM_COMMIT   the exact commit that tag resolves to - a tag names the
#                     release, this pins the bytes, and it is what gets stamped
#                     into every binary and printed in the release notes
#
# UPSTREAM_URL overrides where upstream is cloned from; the tests point it at a
# local fixture repository so they can run this without network.
set -euo pipefail

PATCHES="${1:?usage: apply-patches.sh <patches-root> [version]}"
OVERRIDE="${2:-}"
UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/mongodb/mongo-tools.git}"

# No version to type: resolve the NEWEST upstream release of the major this repo
# carries patches for (tools-major.txt -> newest 100.x, e.g. 100.17.0 or newer).
V="$(bash "$PATCHES/releases/newest-release.sh" "$PATCHES" "$OVERRIDE")"
MAJOR="${V%%.*}"
echo "Building upstream MongoDB Database Tools ${V}."

# Clone ONLY that one upstream release, shallow:
#   --branch "$V"     the newest ${MAJOR}.x RELEASE tag, never a branch head or a
#                     commit between releases;
#   --single-branch   fetch that one ref and no other heads;
#   --depth 1         just the tag's commit, no history behind it.
# mongo-tools vendors its Go dependencies in-tree (vendor/), so there are no
# submodules to init and no module download to do.
git clone --quiet --depth 1 --single-branch --branch "$V" "$UPSTREAM_URL" toolssrc
COMMIT="$(git -C toolssrc rev-parse HEAD)"
echo "Cloned ${UPSTREAM_URL} tag ${V} at commit ${COMMIT} (depth 1, single branch)."

# Move the upstream tree up beside the patches checkout, so the build sees a
# normal mongo-tools tree at $PWD and `go build ./mongodump/main` works with no
# path juggling.
#
# dotglob is what moves the DOTFILES - .git, .gitignore, .github and the rest -
# so `toolssrc/*` is the WHOLE tree and there is nothing left to move
# afterwards. It is deliberately ONE mv: node-patches' first run added a second,
# explicit `mv toolssrc/.git .` after this line and killed all thirteen of its
# builds seconds after cloning, because the glob had already taken .git and mv
# answered "cannot stat". tests/workflow-logic.sh checks that this stays one mv.
shopt -s dotglob
mv toolssrc/* .
shopt -u dotglob
# Nothing may be left behind: rmdir REFUSES a non-empty directory, so this is
# the assertion that the move was complete, not just cleanup.
rmdir toolssrc
# And the .git the move was for is really here - `git apply` below needs it, and
# so does anything that asks the tree what it is.
[ -d .git ] || { echo "::error::The upstream tree's .git did not reach the workspace root."; exit 1; }

# Apply the patches - checksum-verified first, in name order - onto the pristine
# upstream tree. There is ONE section, dist/all, and dist/README.md says why: a
# single checkout here cross-compiles every target, so a patch cannot be
# per-platform in the way a Node.js one is; a patch that concerns one GOOS or
# GOARCH carries a Go build constraint instead.
applied=0
dir="$PATCHES/dist/all"
if [ -d "$dir" ]; then
  for p in "$dir"/*.patch; do
    [ -e "$p" ] || continue
    n="$(basename "$p")"
    # The checksum BEFORE the patch is applied, from inside the section
    # directory (that is where the .sha256sum records the bare name), so a
    # corrupted or hand-edited patch fails loudly instead of applying wrong.
    ( cd "$dir" && sha256sum -c "${n%.patch}.sha256sum" )
    echo "Applying all/${n}"
    git apply "$p"
    applied=$((applied + 1))
  done
fi
if [ "$applied" -eq 0 ]; then
  # Not a warning and not a failure: the wekan/mongo-tools fork it replaced
  # carried no source changes at all, only the build. dist/ is where a patch
  # goes the day a tool needs one to compile for a platform upstream does not
  # build, and until then this repo is upstream plus a build.
  echo "No patches in dist/all - building pristine upstream ${V}."
else
  echo "Applied ${applied} patch(es) onto upstream ${V}."
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Source (${V})"
    echo ""
    echo "| Upstream | Branch | Tag | Commit | Patches applied |"
    echo "|----------|--------|-----|--------|-----------------|"
    echo "| mongodb/mongo-tools | ${MAJOR}.x | ${V} | \`${COMMIT}\` | ${applied} |"
  } >> "$GITHUB_STEP_SUMMARY"
fi
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "VERSION=$V" >> "$GITHUB_ENV"
  echo "UPSTREAM_COMMIT=$COMMIT" >> "$GITHUB_ENV"
  # The version string stamped into every binary, and the tag the release is
  # published under: both are the upstream version, because that is what this
  # is - upstream at that release, plus the patches in dist/.
  echo "TOOLS_VER=$V" >> "$GITHUB_ENV"
  echo "TOOLS_COMMIT=$COMMIT" >> "$GITHUB_ENV"
  echo "RELEASE_TAG=$V" >> "$GITHUB_ENV"
fi

printf 'VERSION=%s\nUPSTREAM_COMMIT=%s\nPATCHES_APPLIED=%s\n' "$V" "$COMMIT" "$applied"
