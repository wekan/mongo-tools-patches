#!/usr/bin/env bash
# What the release workflows do, checked WITHOUT a runner and without the
# network.
#
# The build itself is eight tools times forty-two platforms on a GitHub runner, so
# the failures worth catching here are the ones that kill a run in its first
# seconds - and in the sibling repo that is exactly what happened: wekan/node-patches'
# first run died in every one of its thirteen builds, three seconds after cloning,
# on a `mv` that could never work, and nothing was published. That class of bug is
# what this file exists for.
#
# It does not RE-WRITE the workflows' logic and then check the copy. The logic is
# in scripts - releases/newest-release.sh, releases/apply-patches.sh,
# .github/scripts/build-tools.sh - and this RUNS those scripts, against a local
# fixture repository and a stubbed Go, so a passing test means the real code
# behaves. The workflows are then checked to call exactly those scripts.
#
#   ./tests/workflow-logic.sh
#
# Exit 0 when everything holds, 1 with the failures listed at the end.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALL="$ROOT/.github/workflows/release-all.yml"
MISSING="$ROOT/.github/workflows/release-all-missing.yml"

fails=0
ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── 1. Every script parses, and the workflows call the scripts that exist ─────
#
# A typo in a script is a run that dies on the runner; a workflow naming a script
# that is not there is the same failure one step earlier. Both are free to catch.
echo "The scripts parse, and the workflows call scripts that exist:"

for s in "$ROOT/releases/newest-release.sh" "$ROOT/releases/apply-patches.sh" \
         "$ROOT/releases/update-dependencies.sh" \
         "$ROOT/.github/scripts/build-tools.sh" "$ROOT/tests/patches-apply.sh"; do
  bash -n "$s" 2>/dev/null && ok "bash -n $(basename "$s")" \
                           || fail "$(basename "$s") does not parse"
done
sh -n "$ROOT/.github/scripts/release-assets.sh" 2>/dev/null \
  && ok "sh -n release-assets.sh" || fail "release-assets.sh does not parse"

for wf in "$ALL" "$MISSING"; do
  n="$(basename "$wf")"
  for p in $(grep -oE '_patches/[A-Za-z0-9_./-]+\.sh' "$wf" | sort -u); do
    [ -f "$ROOT/${p#_patches/}" ] && ok "$n calls ${p#_patches/}" \
                                  || fail "$n calls ${p#_patches/}, which is not in this repo"
  done
done

# The build writes to out/ and the workflows upload out/ - dist/ is the patch
# sections here, and a workflow uploading dist/* would publish the patches and
# none of the binaries.
outdir="$(grep -E '^out=' "$ROOT/.github/scripts/build-tools.sh" | sed 's/.*:-\([a-z]*\)}.*/\1/')"
[ "$outdir" = "out" ] && ok "build-tools.sh writes to out/" \
                      || fail "build-tools.sh's output directory is '$outdir', not out/"
for wf in "$ALL" "$MISSING"; do
  n="$(basename "$wf")"
  grep -q 'assets=( out/\* )' "$wf" && ok "$n uploads out/" \
                                    || fail "$n does not upload out/ - dist/ here is the patch sections"
done

# ── 2. Resolving the upstream source ref ─────────────────────────────────────
echo
echo "The upstream source defaults to master and accepts an explicit ref:"

UP="$TMP/upstream"
mkdir -p "$UP"
(
  cd "$UP" || exit 1
  git init -q .
  printf 'hello\n' > hello.txt
  printf 'module github.com/mongodb/mongo-tools\n\ngo 1.26.4\n' > go.mod
  mkdir -p mongodump/main
  printf 'package main\n' > mongodump/main/mongodump.go
  git add -A
  git -c user.email=t@t -c user.name=t commit -qm "fixture upstream"
  for t in 100.9.0 100.9.5 100.17.0 100.18.0-rc0 r4.2.4 99.9.9; do git tag "$t"; done
) || fail "could not build the fixture upstream repository"

got="$(UPSTREAM_URL="file://$UP" bash "$ROOT/releases/newest-release.sh" "$ROOT" 2>/dev/null)"
[ "$got" = "master" ] && ok "master is the default source ref" \
  || fail "expected master, got '$got'"

got="$(UPSTREAM_URL="file://$UP" bash "$ROOT/releases/newest-release.sh" "$ROOT" 100.9.0 2>/dev/null)"
[ "$got" = "100.9.0" ] && ok "an explicit ref overrides master" \
  || fail "the ref override printed '$got'"

# ── 3. Cloning upstream and applying the patches ─────────────────────────────
#
# The move of the upstream tree into the workspace root is the step that killed
# every build in the sibling repo, so it is run here for real: a fixture clone, a
# patches checkout beside it, and the same script the workflows call.
echo
echo "Upstream is cloned into the workspace and the patches are applied:"

# A patches checkout with one patch in it, so the apply loop is exercised rather
# than skipped. The rest of the repo's own files are the real ones.
PATCHES="$TMP/patches"
mkdir -p "$PATCHES/releases" "$PATCHES/dist/all"
cp "$ROOT/releases/newest-release.sh" "$ROOT/releases/apply-patches.sh" "$PATCHES/releases/"
cat > "$PATCHES/dist/all/hello-patched.patch" <<'PATCH'
--- a/hello.txt
+++ b/hello.txt
@@ -1 +1 @@
-hello
+patched
PATCH
( cd "$PATCHES/dist/all" && sha256sum hello-patched.patch > hello-patched.sha256sum )

run_apply() {   # <workspace> -> runs apply-patches.sh there, log in $TMP/apply.log
  rm -rf "$1"; mkdir -p "$1/_patches"
  cp -r "$PATCHES"/. "$1/_patches/"
  ( cd "$1" && UPSTREAM_URL="file://$UP" \
      bash _patches/releases/apply-patches.sh _patches master ) >"$TMP/apply.log" 2>&1
}

WS="$TMP/ws"
if run_apply "$WS"; then
  ok "it succeeds against the fixture upstream"
else
  fail "apply-patches.sh failed: $(tail -2 "$TMP/apply.log" | tr '\n' ' ')"
fi
[ -d "$WS/.git" ]         && ok "the upstream .git ends up at the workspace root" \
                          || fail ".git did not reach the workspace root"
[ -f "$WS/go.mod" ]       && ok "so do the ordinary files (go.mod, which setup-go reads)" \
                          || fail "go.mod did not reach the workspace root"
[ -f "$WS/hello.txt" ]    && ok "so does the rest of the tree" \
                          || fail "the tree did not reach the workspace root"
[ ! -e "$WS/toolssrc" ]   && ok "toolssrc is gone, so nothing was left behind" \
                          || fail "toolssrc survived the move - part of the tree is still in it"
[ -d "$WS/_patches" ]     && ok "the patches checkout is left where it was" \
                          || fail "_patches was disturbed by the move"
grep -qx "patched" "$WS/hello.txt" 2>/dev/null \
  && ok "the patch was applied" \
  || fail "hello.txt was not patched - the apply loop did not run"
grep -q 'PATCHES_APPLIED=1' "$TMP/apply.log" \
  && ok "it reports how many patches it applied" \
  || fail "apply-patches.sh did not report PATCHES_APPLIED=1"
grep -Eq 'VERSION=master-[0-9a-f]{7,}' "$TMP/apply.log" \
  && ok "the build identity pins the master commit" \
  || fail "the master build identity is not commit-pinned"

# NEGATIVE: a patch whose checksum does not match must not be applied. The
# checksum is verified BEFORE `git apply`, which is the whole reason it exists -
# without this check the test above would pass just as well with no verification
# at all.
printf 'deadbeef  hello-patched.patch\n' > "$PATCHES/dist/all/hello-patched.sha256sum"
if run_apply "$TMP/ws-bad"; then
  fail "a patch with a WRONG checksum was applied anyway"
else
  ok "a wrong checksum fails the build before the patch is applied"
fi
( cd "$PATCHES/dist/all" && sha256sum hello-patched.patch > hello-patched.sha256sum )

# NEGATIVE: the sibling repo's first-run bug, in its exact form - a second,
# explicit `mv toolssrc/.git .` after the dotglob move. dotglob already took
# .git, so mv answers "cannot stat" and, under set -e, kills the step.
sed 's#^mv toolssrc/\* \.$#mv toolssrc/* .\nmv toolssrc/.git .#' \
  "$PATCHES/releases/apply-patches.sh" > "$TMP/apply-bug.sh"
cp "$TMP/apply-bug.sh" "$PATCHES/releases/apply-patches.sh"
if run_apply "$TMP/ws-bug"; then
  fail "re-adding the old double-move did NOT fail - this test would not catch the regression"
else
  ok "re-adding a second 'mv toolssrc/.git .' fails, as it did on the runner"
fi
cp "$ROOT/releases/apply-patches.sh" "$PATCHES/releases/apply-patches.sh"

# And statically, because the line is unmistakable. Comments are dropped first -
# the script's own comments explain the bug and name the line.
if grep -vE '^\s*#' "$ROOT/releases/apply-patches.sh" | grep -q 'mv toolssrc/\.git'; then
  fail "apply-patches.sh moves toolssrc/.git a second time - dotglob already moved it"
else
  ok "apply-patches.sh does not move .git twice"
fi

# ── 4. The build: every tool, every target, a checksum beside each ───────────
#
# Run with a STUBBED go, so this checks the script's own logic - the target list,
# the skip list, the checksums, what it treats as fatal - in a second, without a
# Go toolchain. One target is made to "not compile", because that is a normal
# outcome here and must not fail the build.
echo
echo "The build covers every tool and target, and survives one that does not compile:"

mkdir -p "$TMP/bin"
cat > "$TMP/bin/go" <<'STUB'
#!/bin/sh
# Stand-in for `go build ...`: writes the -o file, or refuses for the one target
# this test wants to see skipped.
out=""
while [ $# -gt 0 ]; do
  case "$1" in -o) out="$2"; shift ;; esac
  shift
done
[ -n "$out" ] || exit 1
case "$out" in *mongostat-loong64*) echo "stub: does not compile" >&2; exit 1 ;; esac
mkdir -p "$(dirname "$out")"
printf 'stub binary\n' > "$out"
STUB
chmod +x "$TMP/bin/go"

BUILD="$TMP/build"
mkdir -p "$BUILD"
( cd "$BUILD" && PATH="$TMP/bin:$PATH" TOOLS_VER=100.17.0 TOOLS_COMMIT=abc123 \
    bash "$ROOT/.github/scripts/build-tools.sh" ) >"$TMP/build.log" 2>&1 \
  && ok "it succeeds when one target does not compile" \
  || fail "build-tools.sh failed: $(tail -2 "$TMP/build.log" | tr '\n' ' ')"

bins="$(find "$BUILD/out" -type f ! -name '*.sha256sum' 2>/dev/null | wc -l | tr -d ' ')"
sums="$(find "$BUILD/out" -type f -name '*.sha256sum' 2>/dev/null | wc -l | tr -d ' ')"
# 8 tools x 42 targets = 336, less the one target stubbed to fail. The expected
# count moves with the canonical target registry rather than being loosened.
[ "$bins" = "335" ] && ok "8 tools x 42 targets, less the one that does not compile ($bins)" \
                    || fail "expected 335 binaries, got $bins"
[ "$sums" = "$bins" ] && ok "a .sha256sum beside every binary ($sums)" \
                      || fail "$bins binaries but $sums checksums"
targets="$(sed -n '/^TARGETS="/,/^"$/p' "$ROOT/.github/scripts/build-tools.sh" |
  sed -n 's/^  \([^ ]*\) .*/\1/p')"
expected="amd64 arm64 armhf armv6 armel i386 ppc64le s390x riscv64 loong64 win64 win-arm64 win32 mac-amd64 mac-arm64 freebsd-amd64 freebsd-i386 freebsd-armel freebsd-armv6 freebsd-armv7 freebsd-arm64 aix-ppc64 dragonfly-amd64 mips mipsle mips64 mips64le ppc64 netbsd-i386 netbsd-amd64 netbsd-armel netbsd-armv6 netbsd-armv7 netbsd-arm64 openbsd-i386 openbsd-amd64 openbsd-armel openbsd-armv6 openbsd-armv7 openbsd-arm64 openbsd-ppc64 openbsd-riscv64"
missing_targets=""
for target in $expected; do
  printf '%s\n' "$targets" | grep -qxF "$target" || missing_targets="$missing_targets $target"
done
[ -z "$missing_targets" ] && ok "all 42 compile-proven native targets are registered" \
  || fail "compile-proven targets are missing:$missing_targets"
[ "$(printf '%s\n' "$targets" | sort -u | wc -l | tr -d ' ')" = 42 ] \
  && ok "the target registry has no duplicate names" || fail "the target registry is duplicated"
grep -q 'tmp_root="${TMPDIR:-$PWD/.tools/tmp}"' "$ROOT/.github/scripts/build-tools.sh" \
  && ok "compiler diagnostics use configured .tools/tmp" \
  || fail "compiler diagnostics do not honor TMPDIR/.tools/tmp"
[ -e "$BUILD/out/mongostat-loong64" ] \
  && fail "the target that does not compile still produced a binary" \
  || ok "the target that does not compile produced nothing, and did not fail the run"
grep -q 'skipped mongostat-loong64 (does not compile)' "$TMP/build.log" \
  && ok "it says which target did not compile" \
  || fail "the build did not report the skipped target"
( cd "$BUILD/out" && sha256sum -c mongodump-amd64.sha256sum >/dev/null 2>&1 ) \
  && ok "the checksums are in the format sha256sum -c reads" \
  || fail "mongodump-amd64.sha256sum does not verify with sha256sum -c"
grep -q '  mongodump-amd64$' "$BUILD/out/mongodump-amd64.sha256sum" \
  && ok "and they record the bare file name" \
  || fail "the checksum file does not record the bare name"
# Windows binaries carry .exe, and their checksum is named after the binary.
[ -e "$BUILD/out/mongodump-win64.exe" ] && [ -e "$BUILD/out/mongodump-win64.exe.sha256sum" ] \
  && ok "Windows targets get .exe, with the checksum named after it" \
  || fail "the Windows binary or its checksum is missing/misnamed"

# ── 5. What "already on the release" means ───────────────────────────────────
#
# Release All Missing hands the release's asset list to the SAME build script.
# A binary counts as present only when its checksum is there too: a binary whose
# .sha256sum upload failed is the half-published state that workflow exists to
# repair, and calling it present would leave it broken forever.
echo
echo "A binary counts as already published only with its checksum beside it:"

SKIPDIR="$TMP/skip"
mkdir -p "$SKIPDIR"
cat > "$SKIPDIR/existing.txt" <<'LIST'
mongodump-amd64
mongodump-amd64.sha256sum
mongodump-arm64
LIST
( cd "$SKIPDIR" && PATH="$TMP/bin:$PATH" TOOLS_VER=100.17.0 SKIP_LIST=existing.txt \
    bash "$ROOT/.github/scripts/build-tools.sh" ) >"$TMP/skip.log" 2>&1 \
  || fail "build-tools.sh with a skip list failed: $(tail -2 "$TMP/skip.log" | tr '\n' ' ')"

grep -q '  have    mongodump-amd64$' "$TMP/skip.log" \
  && ok "a fully published binary is not rebuilt" \
  || fail "mongodump-amd64 was rebuilt although it and its checksum are on the release"
grep -q '  built   mongodump-arm64$' "$TMP/skip.log" \
  && ok "a binary whose checksum is missing IS rebuilt" \
  || fail "mongodump-arm64 was treated as present although its .sha256sum is not on the release"
[ ! -e "$SKIPDIR/out/mongodump-amd64" ] \
  && ok "and the skipped one is not written again" \
  || fail "the skipped binary was written anyway"

# NEGATIVE: nothing built and nothing skipped is a broken toolchain, not a
# complete release, and it must fail.
cat > "$TMP/bin/go" <<'STUB'
#!/bin/sh
echo "stub: nothing compiles" >&2
exit 1
STUB
chmod +x "$TMP/bin/go"
DEAD="$TMP/dead"; mkdir -p "$DEAD"
if ( cd "$DEAD" && PATH="$TMP/bin:$PATH" TOOLS_VER=100.17.0 \
       bash "$ROOT/.github/scripts/build-tools.sh" ) >/dev/null 2>&1; then
  fail "a build that produced NOTHING succeeded - a broken toolchain would publish an empty release"
else
  ok "a build that produces nothing at all fails"
fi

# ── 6. Every patch is a complete, checksummed, documented trio ───────────────
#
# The build runs `sha256sum -c <name>.sha256sum` from inside dist/all before
# applying, so the checksum file must record the BARE name. A stale checksum, or
# a path in it, fails the build after the clone.
echo
echo "Every patch in dist/ is a complete, checksummed, documented trio:"
found=0
for p in "$ROOT"/dist/*/*.patch; do
  [ -e "$p" ] || continue
  found=$((found+1))
  d="$(dirname "$p")"; n="$(basename "$p" .patch)"; rel="$(basename "$d")/$n"
  miss=""
  [ -f "$d/$n.sha256sum" ] || miss="$miss .sha256sum"
  [ -f "$d/$n.md" ]        || miss="$miss .md"
  if [ -n "$miss" ]; then fail "$rel is missing:$miss"; continue; fi
  grep -q "  $n.patch\$" "$d/$n.sha256sum" \
    || fail "$rel.sha256sum does not name the bare file '$n.patch' (CI checks it from inside the section)"
  if ( cd "$d" && sha256sum -c "$n.sha256sum" >/dev/null 2>&1 ); then
    ok "$rel"
  else
    fail "$rel checksum does not match the patch - recompute it in the section directory"
  fi
done
[ "$found" -eq 0 ] && ok "no patches yet - upstream builds as it is (see dist/README.md)"

# ── 7. gh talks to THIS repository, not the one in the working directory ─────
#
# This is what the first real run died of, after building all 128 binaries:
#
#   HTTP 403: Resource not accessible by integration
#   (https://api.github.com/repos/mongodb/mongo-tools/releases)
#
# gh works out which repository to act on from the git remote of the working
# directory - and by publish time the working directory IS the upstream clone,
# whose origin is mongodb/mongo-tools. So every step that runs gh has to say
# which repository it means. GH_REPO is how gh is told.
echo
echo "Every step that runs gh names this repository:"
for wf in "$ALL" "$MISSING"; do
  n="$(basename "$wf")"
  tok="$(grep -c 'GH_TOKEN: \${{ secrets.GITHUB_TOKEN }}' "$wf")"
  rep="$(grep -c 'GH_REPO: \${{ github.repository }}' "$wf")"
  [ "$tok" = "$rep" ] && [ "$tok" != "0" ] \
    && ok "$n: $tok step(s) with a token, $rep with GH_REPO" \
    || fail "$n has $tok GH_TOKEN step(s) but $rep GH_REPO - gh would guess the repository from the upstream clone"
done

# ── 8. Moving source and dependency inputs stay explicit ─────────────────────
echo
echo "The workflows select newest source, toolchain and dependencies:"
for wf in "$ALL" "$MISSING"; do
  n="$(basename "$wf")"
  grep -q 'go-version: stable' "$wf" && ok "$n installs stable Go" \
    || fail "$n does not install the newest stable Go"
  grep -q 'releases/update-dependencies.sh' "$wf" && ok "$n upgrades dependencies" \
    || fail "$n does not run update-dependencies.sh"
done
grep -q 'go get -u ./\.\.\.' "$ROOT/releases/update-dependencies.sh" \
  && ok "the whole module graph is upgraded" \
  || fail "update-dependencies.sh does not upgrade every package dependency"

echo
if [ "$fails" -eq 0 ]; then
  echo "workflow-logic: everything holds."
else
  echo "workflow-logic: $fails check(s) FAILED."
fi
exit $(( fails > 0 ))
