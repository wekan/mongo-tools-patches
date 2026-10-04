#!/usr/bin/env bash
# What the release workflows do, checked WITHOUT a runner and without the
# network.
#
# The build itself is eight tools times forty-three platforms on a GitHub runner, so
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
export PYTHONDONTWRITEBYTECODE=1

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
         "$ROOT/releases/update-dependencies.sh" "$ROOT/releases/apply-vendor-patches.sh" \
         "$ROOT/.github/scripts/build-tools.sh" "$ROOT/.github/scripts/upload-release-assets.sh" \
         "$ROOT/tests/patches-apply.sh" \
         "$ROOT/tests/no-telemetry-upstream.sh" "$ROOT/tests/sdk-telemetry.sh"; do
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
for wf in "$ALL" "$MISSING"; do
  grep -q 'timeout-minutes: 180' "$wf" \
    && ok "$(basename "$wf") allows the expanded matrix three hours" \
    || fail "$(basename "$wf") still has the old seventeen-target timeout"
done

# The build writes to out/ and the binaries are attached from out/ - dist/ is the patch
# sections here, and a workflow uploading dist/* would publish the patches and
# none of the binaries.
outdir="$(grep -E '^out=' "$ROOT/.github/scripts/build-tools.sh" | sed 's/.*:-\([a-z]*\)}.*/\1/')"
[ "$outdir" = "out" ] && ok "build-tools.sh writes to out/" \
                      || fail "build-tools.sh's output directory is '$outdir', not out/"
grep -q 'out="${OUT:-out}"' "$ROOT/.github/scripts/attach-finished.sh" \
  && ok "attach-finished.sh attaches from out/" \
  || fail "attach-finished.sh does not read out/ - dist/ here is the patch sections"
for wf in "$ALL" "$MISSING"; do
  n="$(basename "$wf")"
  ! grep -vE '^\s*#' "$wf" | grep -q 'dist/\*' && ok "$n never uploads dist/*" \
    || fail "$n uploads dist/* - that is the patch sections, not the binaries"
done

# ── 2. Resolving the upstream source ref ─────────────────────────────────────
echo
echo "The upstream source defaults to master and accepts an explicit ref:"

UP="$TMP/upstream"
mkdir -p "$UP"
(
  cd "$UP" || exit 1
  git init -q -b master .
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
      bash _patches/releases/apply-patches.sh _patches "${2:-master}" ) >"$TMP/apply.log" 2>&1
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

# A raw commit is a valid fetch input but GitHub rejects it as a release tag.
commit="$(git -C "$UP" rev-parse master)"
if run_apply "$TMP/ws-commit" "$commit"; then
  grep -qx "VERSION=upstream-$commit" "$TMP/apply.log" \
    && ok "immutable source gets a GitHub-safe release tag" \
    || fail "raw commit was used as the release tag"
  grep -qx "UPSTREAM_COMMIT=$commit" "$TMP/apply.log" \
    && ok "full upstream commit remains recorded" \
    || fail "upstream commit changed when formatting the release tag"
else
  fail "fetching an immutable source commit failed"
fi

# NEGATIVE: a patch whose checksum does not match must not be applied. The
# checksum is verified BEFORE `git apply`, which is the whole reason it exists -
# without this check the test above would pass just as well with no verification
# at all.
printf '0000000000000000000000000000000000000000000000000000000000000000  hello-patched.patch\n' > "$PATCHES/dist/all/hello-patched.sha256sum"
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

# Compile-matrix tests use a real audit of a minimal source fixture. Only Go
# compilation is stubbed; the production audit has no environment bypass.
AUDIT_REPO="$TMP/build-scripts"
mkdir -p "$AUDIT_REPO/.github/scripts" "$AUDIT_REPO/releases"
cp "$ROOT/.github/scripts/build-tools.sh" "$AUDIT_REPO/.github/scripts/"
cp "$ROOT/releases/audit-telemetry.py" "$ROOT/releases/check-telemetry.py" "$ROOT/releases/risk-audit.py" "$AUDIT_REPO/releases/"
prepare_build_fixture() {
  mkdir -p "$1/vendor"
  printf 'module fixture\n' > "$1/go.mod"
  : > "$1/go.sum"
  : > "$1/vendor/modules.txt"
  python3 - "$AUDIT_REPO" "$1" <<'PYFIXTURE'
import importlib.util, json, pathlib, sys
repo = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location('audit', repo / 'releases/audit-telemetry.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)
(repo / 'releases/telemetry-audit.json').write_text(json.dumps({'trees': audit.snapshot(sys.argv[2])}))
spec = importlib.util.spec_from_file_location('risk', repo / 'releases/risk-audit.py')
risk = importlib.util.module_from_spec(spec); spec.loader.exec_module(risk)
policy = {'roots':['.'], 'initialized':True}
policy['files'] = risk.collect(sys.argv[2], policy)
(repo / 'releases/upstream-risk-baseline.json').write_text(json.dumps(policy))
PYFIXTURE
}

BUILD="$TMP/build"
mkdir -p "$BUILD"
prepare_build_fixture "$BUILD"
( cd "$BUILD" && PATH="$TMP/bin:$PATH" TOOLS_VER=100.17.0 TOOLS_COMMIT=abc123 \
    bash "$AUDIT_REPO/.github/scripts/build-tools.sh" ) >"$TMP/build.log" 2>&1 \
  && ok "it succeeds when one target does not compile" \
  || fail "build-tools.sh failed: $(tail -2 "$TMP/build.log" | tr '\n' ' ')"

bins="$(find "$BUILD/out" -type f ! -name '*.sha256sum' 2>/dev/null | wc -l | tr -d ' ')"
sums="$(find "$BUILD/out" -type f -name '*.sha256sum' 2>/dev/null | wc -l | tr -d ' ')"
# 8 tools x 43 targets = 344, less the one target stubbed to fail. The expected
# count moves with the canonical target registry rather than being loosened.
[ "$bins" = "343" ] && ok "8 tools x 43 targets, less the one that does not compile ($bins)" \
                    || fail "expected 343 binaries, got $bins"
[ "$sums" = "$bins" ] && ok "a .sha256sum beside every binary ($sums)" \
                      || fail "$bins binaries but $sums checksums"
targets="$(sed -n '/^TARGETS="/,/^"$/p' "$ROOT/.github/scripts/build-tools.sh" |
  sed -n 's/^  \([^ ]*\) .*/\1/p')"
expected="amd64 arm64 armhf armv6 armel i386 ppc64le s390x riscv64 loong64 win64 win-arm64 win32 mac-amd64 mac-arm64 freebsd-amd64 freebsd-i386 freebsd-armel freebsd-armv6 freebsd-armv7 freebsd-arm64 aix-ppc64 dragonfly-amd64 mips mipsle mips64 mips64le ppc64 netbsd-i386 netbsd-amd64 netbsd-armel netbsd-armv6 netbsd-armv7 netbsd-arm64 openbsd-i386 openbsd-amd64 openbsd-armel openbsd-armv6 openbsd-armv7 openbsd-arm64 openbsd-ppc64 openbsd-riscv64 android-arm64"
missing_targets=""
for target in $expected; do
  printf '%s\n' "$targets" | grep -qxF "$target" || missing_targets="$missing_targets $target"
done
[ -z "$missing_targets" ] && ok "all 43 compile-proven native targets are registered" \
  || fail "compile-proven targets are missing:$missing_targets"
[ "$(printf '%s\n' "$targets" | sort -u | wc -l | tr -d ' ')" = 43 ] \
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

# A compiled telemetry implementation is fatal, not a skipped architecture.
cp "$TMP/bin/go" "$TMP/good-go"
sed 's/stub binary/beacon.ferretdb.com/' "$TMP/good-go" > "$TMP/bin/go"
BAD_BINARY="$TMP/bad-binary"
prepare_build_fixture "$BAD_BINARY"
if ( cd "$BAD_BINARY" && PATH="$TMP/bin:$PATH" TOOLS_VER=100.17.0 \
     bash "$AUDIT_REPO/.github/scripts/build-tools.sh" ) >"$TMP/bad-binary.log" 2>&1; then
  fail "telemetry in a compiled artifact did not stop the matrix"
elif grep -q '::error::Telemetry audit failed' "$TMP/bad-binary.log" &&
     ! grep -q 'skipped .*does not compile' "$TMP/bad-binary.log"; then
  ok "telemetry in a compiled artifact stops the matrix with an error"
else
  fail "binary telemetry failure was swallowed or reported as unsupported"
fi
cp "$TMP/good-go" "$TMP/bin/go"
# Restore the source fixture inventory before testing source drift.
prepare_build_fixture "$BUILD"

# Ordinary changed hashes must compile; actual indicators must stop, including
# in nested directories named out/ (which are source, not root build output).
mkdir -p "$BUILD/vendor/example/out"
printf 'package reporting\n' > "$BUILD/vendor/example/out/new.go"
if ( cd "$BUILD" && PATH="$TMP/bin:$PATH" TOOLS_VER=100.17.0 \
     bash "$AUDIT_REPO/.github/scripts/build-tools.sh" ) >"$TMP/drift.log" 2>&1; then
  ok "ordinary vendored source drift does not require approval"
else
  fail "ordinary source drift blocked compilation"
fi
printf 'package reporting; var endpoint = "https://new.example/upload"\n' > "$BUILD/vendor/example/out/new.go"
if ( cd "$BUILD" && PATH="$TMP/bin:$PATH" TOOLS_VER=100.17.0 \
     bash "$AUDIT_REPO/.github/scripts/build-tools.sh" ) >"$TMP/indicator.log" 2>&1; then
  fail "new outbound URL reached compilation"
elif grep -q 'Automated risk indicators found' "$TMP/indicator.log"; then
  ok "new outbound URL stops before compilation"
else
  fail "indicator check failed for an unexpected reason"
fi

# ── 5. What "already on the release" means ───────────────────────────────────
#
# Release All Missing hands the release's asset list to the SAME build script.
# A binary counts as present only when its checksum is there too: a binary whose
# .sha256sum upload failed is the half-published state that workflow exists to
# repair, and calling it present would leave it broken forever.
echo
echo "A binary counts as already published only with its checksum beside it:"

SKIPDIR="$TMP/skip"
mkdir -p "$SKIPDIR/.tools"
cat > "$SKIPDIR/.tools/existing.txt" <<'LIST'
mongodump-amd64
mongodump-amd64.sha256sum
mongodump-arm64
LIST
prepare_build_fixture "$SKIPDIR"
( cd "$SKIPDIR" && PATH="$TMP/bin:$PATH" TOOLS_VER=100.17.0 SKIP_LIST=.tools/existing.txt \
    bash "$AUDIT_REPO/.github/scripts/build-tools.sh" ) >"$TMP/skip.log" 2>&1 \
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
prepare_build_fixture "$DEAD"
if ( cd "$DEAD" && PATH="$TMP/bin:$PATH" TOOLS_VER=100.17.0 \
       bash "$AUDIT_REPO/.github/scripts/build-tools.sh" ) >/dev/null 2>&1; then
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

# ── 7b. Each binary is on the release as soon as IT is finished ───────────
#
# Not after the whole 344-binary build: build-tools.sh attaches every binary
# with its .sha256sum right after it compiled and passed the telemetry audit
# (MONGO_TOOLS_PUBLISH), the release is created before the build so there is
# something to attach to, and always() steps keep what a CANCELLED run finished.
echo
echo "Each binary is attached the moment it is finished, and a cancel keeps them:"
step_block() {   # <workflow> <step-name-fragment> -> that step's lines
  awk -v want="$2" '/^      - (name|uses):/{inside=index($0,want)>0} inside' "$1"
}
step_if() {      # <workflow> <step-name-fragment> -> that step's if: value
  step_block "$1" "$2" | sed -n 's/^        if: *//p' | head -1
}
step_line() {    # <workflow> <step-name-fragment> -> line number of the step
  grep -n "^      - name: .*$2" "$1" | head -1 | cut -d: -f1
}
for pair in "$ALL|Create the release|Cross-compile" "$MISSING|Create the release|Build only what is missing"; do
  wf="${pair%%|*}"; rest="${pair#*|}"; create="${rest%%|*}"; build="${rest#*|}"
  n="$(basename "$wf")"
  [ "$(awk '/^jobs:/{j=1;next} j && /^  [A-Za-z0-9_-]+:$/{c++} END{print c+0}' "$wf")" = 1 ] \
    && ok "$n builds and attaches in one job" || fail "$n has more than one job"
  ! grep -qE 'actions/(upload|download)-artifact' "$wf" \
    && ok "$n does not hand binaries to a later job to publish" \
    || fail "$n passes binaries between jobs - the building job must attach them"
  cl="$(step_line "$wf" "$create")"; bl="$(step_line "$wf" "$build")"
  [ -n "$cl" ] && [ -n "$bl" ] && [ "$cl" -lt "$bl" ] \
    && ok "$n creates the release BEFORE the build" \
    || fail "$n does not create the release before building - nothing to attach each binary to"
  step_block "$wf" "$create" | grep -q '^        id: release$' \
    && ok "$n's release step has id: release" || fail "$n's release step has no id: release"
  step_block "$wf" "$build" | grep -q '^        id: build$' \
    && ok "$n's build step has id: build" || fail "$n's build step has no id: build"
  step_block "$wf" "$build" | grep -q 'MONGO_TOOLS_PUBLISH: .*upload-release-assets.sh' \
    && ok "$n's build attaches each binary as it is finished (MONGO_TOOLS_PUBLISH)" \
    || fail "$n's build does not set MONGO_TOOLS_PUBLISH - binaries wait for the whole build"
  # The catch-up and the final check run after a CANCEL, gated on the release
  # existing. NEGATIVE: !cancelled() is exactly what skips them on cancel.
  for step in "Attach any finished binary" "Check that every finished binary"; do
    cond="$(step_if "$wf" "$step")"
    case "$cond" in
      *"always()"*"steps.release.outcome == 'success'"*)
        ok "$n: '$step' runs after a cancel, once the release exists" ;;
      *) fail "$n: '$step' has if: '$cond' - a cancelled run would lose finished binaries" ;;
    esac
  done
  step_block "$wf" "Attach any finished binary" | grep -q 'attach-finished.sh "\$RELEASE_TAG"$' \
    && ok "$n's catch-up attaches only the finished list (attach-finished.sh)" \
    || fail "$n's catch-up does not use attach-finished.sh"
  last="$(awk '/^      - name:/{s=$0} END{print s}' "$wf")"
  step_block "$wf" "${last#*- name: }" | grep -q 'attach-finished.sh "\$RELEASE_TAG" --check' \
    && ok "$n's last step reports any finished binary not on the release" \
    || fail "$n's last step does not run attach-finished.sh --check"
  ! grep -q 'cancelled()' "$wf" && ok "$n has no step that is skipped on cancel" \
    || fail "$n still has a cancelled() condition"
  # NEGATIVE: nothing may upload all of out/ after the whole build - that is
  # the wait-for-everything shape this replaced - nor bypass the retries.
  if grep -vE '^\s*#' "$wf" | grep -qE 'out/\*|\$\{assets'; then
    fail "$n uploads all of out/ after the build instead of each binary as it finishes"
  else
    ok "$n has no step that uploads all of out/ after the build"
  fi
  if grep -vE '^\s*#' "$wf" | grep -qE 'gh release (upload|create) [^#]*(out/|\$\{)'; then
    fail "$n uploads files with a single gh call, bypassing the retries"
  else
    ok "$n has no single-shot gh upload of binaries"
  fi
done

# build-tools.sh itself: each binary must be attached BEFORE the next one is
# built. A stubbed go and a stubbed publish command write one shared log.
ORDER="$TMP/order"; mkdir -p "$ORDER/bin"
cat > "$ORDER/bin/go" <<'STUB'
#!/bin/sh
out=""; while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift ;; esac; shift; done
echo "build $(basename "$out")" >> "$ORDER_LOG"
case "$out" in *mongostat-loong64*) exit 1 ;; esac
printf 'stub binary\n' > "$out"
STUB
cat > "$ORDER/publish" <<'STUB'
#!/bin/sh
# Records what was attached, and checks the checksum exists AND verifies.
tag="$1"; shift
[ -f "$2" ] && ( cd "$(dirname "$2")" && sha256sum -c "$(basename "$2")" >/dev/null 2>&1 ) \
  || { echo "publish-without-checksum $(basename "$1")" >> "$ORDER_LOG"; exit 1; }
grep -qxF "$(basename "$1")" "$FINISHED_LIST" \
  || { echo "publish-unfinished $(basename "$1")" >> "$ORDER_LOG"; exit 1; }
echo "publish $tag $(basename "$1") $(basename "$2")" >> "$ORDER_LOG"
case "$1" in *"${FAIL_PUBLISH:-none}"*) exit 1 ;; esac
STUB
chmod +x "$ORDER/bin/go" "$ORDER/publish"
run_order() {   # [FAIL_PUBLISH asset] -> build in $ORDER/ws with publishing on
  rm -rf "$ORDER/ws"; mkdir -p "$ORDER/ws"; prepare_build_fixture "$ORDER/ws"
  : > "$ORDER/log"
  ( cd "$ORDER/ws" && PATH="$ORDER/bin:$PATH" ORDER_LOG="$ORDER/log" TOOLS_VER=100.17.0 \
      FINISHED_LIST="$ORDER/ws/.tools/finished.list" FAIL_PUBLISH="${1:-none}" \
      MONGO_TOOLS_PUBLISH="$ORDER/publish" RELEASE_TAG=v-test \
      bash "$AUDIT_REPO/.github/scripts/build-tools.sh" ) >"$TMP/order.log" 2>&1
}
if run_order; then ok "a publishing build succeeds"; else
  fail "a publishing build failed: $(tail -2 "$TMP/order.log" | tr '\n' ' ')"; fi
head -3 "$ORDER/log" | tr '\n' '|' | grep -qx 'build bsondump-amd64|publish v-test bsondump-amd64 bsondump-amd64.sha256sum|build mongodump-amd64|' \
  && ok "the first binary is attached, with its checksum, before the second is built" \
  || fail "attach order is wrong: $(head -3 "$ORDER/log" | tr '\n' '|')"
# Every publish directly follows its own build: never batched at the end.
awk '/^build /{b=$2; next} /^publish /{if ($3 != b) bad=1; b=""} END{exit bad}' "$ORDER/log" \
  && ok "every binary is attached right after its own build, never batched" \
  || fail "a binary was attached later than right after its own build"
[ "$(grep -c '^publish ' "$ORDER/log")" = 343 ] \
  && ok "all 343 finished binaries were attached as they finished" \
  || fail "expected 343 attaches, got $(grep -c '^publish ' "$ORDER/log")"
! grep -q 'mongostat-loong64' <(grep '^publish' "$ORDER/log") \
  && ok "the target that did not compile was never attached" \
  || fail "a binary that did not compile was attached"
! grep -qE '^publish-(without-checksum|unfinished)' "$ORDER/log" \
  && ok "nothing was attached before its checksum and finished-list entry existed" \
  || fail "a binary was attached before it was finished: $(grep -E '^publish-' "$ORDER/log" | head -1)"
# NEGATIVE: a failed attach keeps building and fails at the END.
if run_order mongodump-arm64; then
  fail "a failed attach did not fail the build"
else
  grep -q '^build mongotop-android-arm64$' "$ORDER/log" \
    && ok "a failed attach does not stop the build; it fails at the end" \
    || fail "a failed attach stopped the build early"
  grep -q 'not attached to v-test: mongodump-arm64' "$TMP/order.log" \
    && ok "and says which binary was not attached" \
    || fail "the build did not name the binary it could not attach"
fi
# Local use (no MONGO_TOOLS_PUBLISH) attaches nothing - already covered by the
# builds in section 4, which run without it and must not call gh.

# The catch-up: attach-finished.sh attaches only binaries in the finished list
# that the release does not have - never an unlisted (unfinished) file in out/.
GHC="$TMP/ghc"; mkdir -p "$GHC/bin" "$GHC/ws/out" "$GHC/ws/.tools"
cat > "$GHC/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "release upload") shift 3; for a in "$@"; do [ "$a" = --clobber ] || echo "$(basename "$a")" >> "$GHC_LOG"; done ;;
  "release view") cat "$GHC_ASSETS" ;;
  *) exit 2 ;;
esac
STUB
chmod +x "$GHC/bin/gh"
for f in mongodump-amd64 mongodump-arm64 mongodump-i386; do
  printf 'bin %s\n' "$f" > "$GHC/ws/out/$f"; ( cd "$GHC/ws/out" && sha256sum "$f" > "$f.sha256sum" )
done
printf 'half written\n' > "$GHC/ws/out/mongotop-amd64"   # cancelled mid-compile: unlisted
printf 'mongodump-amd64\nmongodump-arm64\n' > "$GHC/ws/.tools/finished.list"
size() { wc -c < "$GHC/ws/out/$1" | tr -d ' '; }
printf 'mongodump-amd64\t%s\nmongodump-amd64.sha256sum\t%s\n' "$(size mongodump-amd64)" "$(size mongodump-amd64.sha256sum)" > "$GHC/assets"
run_catchup() {
  : > "$GHC/log"
  ( cd "$GHC/ws" && PATH="$GHC/bin:$PATH" GHC_LOG="$GHC/log" GHC_ASSETS="$GHC/assets" \
      UPLOAD_RETRY_DELAY=0 bash "$ROOT/.github/scripts/attach-finished.sh" v-test "$@" ) >"$TMP/catchup.log" 2>&1
}
if run_catchup --check; then
  fail "--check passed although a finished binary is not on the release"
else
  grep -q 'mongodump-arm64' "$TMP/catchup.log" && ok "--check fails and names the finished binary that is missing" \
    || fail "--check failed without naming the missing binary"
fi
run_catchup || fail "attach-finished.sh failed: $(tail -2 "$TMP/catchup.log" | tr '\n' ' ')"
[ "$(sort "$GHC/log" | tr '\n' ' ')" = "mongodump-arm64 mongodump-arm64.sha256sum " ] \
  && ok "the catch-up attaches only the finished binary the release lacks, with its checksum" \
  || fail "the catch-up attached: $(tr '\n' ' ' < "$GHC/log")"
# NEGATIVE: unfinished files in out/ are never attached.
! grep -qE 'mongotop-amd64|mongodump-i386' "$GHC/log" \
  && ok "a file in out/ that is not in the finished list is never attached" \
  || fail "the catch-up attached a binary that never finished"

# The script itself, against a stubbed gh: the first upload fails half way, the
# retry must send ONLY what did not arrive, and must then succeed.
GHBIN="$TMP/ghbin"; mkdir -p "$GHBIN"
cat > "$GHBIN/gh" <<'STUB'
#!/usr/bin/env bash
# Stand-in for gh. State in $GH_STATE: uploads.log (one line per upload call),
# assets (name<TAB>size of what the release carries). GH_FAIL_UPLOADS = how many
# upload calls fail; a failing call still "uploads" its first file.
state="$GH_STATE"; touch "$state/assets" "$state/uploads.log"
case "$1 $2" in
  "release upload")
    shift 3; files=(); for a in "$@"; do [ "$a" = --clobber ] || files+=("$a"); done
    echo "${files[*]##*/}" >> "$state/uploads.log"
    calls=$(wc -l < "$state/uploads.log" | tr -d ' ')
    put() { awk -F'\t' -v n="$(basename "$1")" '$1 != n' "$state/assets" > "$state/a.tmp"
            printf '%s\t%s\n' "$(basename "$1")" "$(wc -c < "$1" | tr -d ' ')" >> "$state/a.tmp"
            mv "$state/a.tmp" "$state/assets"; }
    if [ "$calls" -le "${GH_FAIL_UPLOADS:-0}" ]; then put "${files[0]}"; echo "stub: upload failed" >&2; exit 1; fi
    for f in "${files[@]}"; do put "$f"; done ;;
  "release view")
    awk -F'\t' '{print $1"\t"$2}' "$state/assets" ;;
  *) echo "stub gh: unexpected $*" >&2; exit 2 ;;
esac
STUB
chmod +x "$GHBIN/gh"
UP_DIR="$TMP/upload"; mkdir -p "$UP_DIR/out"
for f in mongodump-amd64 mongodump-amd64.sha256sum mongodump-arm64 mongodump-arm64.sha256sum; do
  printf 'bytes of %s\n' "$f" > "$UP_DIR/out/$f"
done
run_upload() {   # <fail-count> -> runs the script with a fresh stub state
  rm -rf "$UP_DIR/state"; mkdir -p "$UP_DIR/state"
  ( cd "$UP_DIR" && PATH="$GHBIN:$PATH" GH_STATE="$UP_DIR/state" GH_FAIL_UPLOADS="$1" \
      UPLOAD_ATTEMPTS=3 UPLOAD_RETRY_DELAY=0 \
      bash "$ROOT/.github/scripts/upload-release-assets.sh" v-test out/* ) >"$TMP/upload.log" 2>&1
}
if run_upload 1; then
  ok "a failed upload is retried and then succeeds"
else
  fail "upload-release-assets.sh did not recover from one failed upload: $(tail -2 "$TMP/upload.log" | tr '\n' ' ')"
fi
[ "$(wc -l < "$UP_DIR/state/uploads.log" | tr -d ' ')" = 2 ] \
  && ok "it took exactly two attempts" || fail "expected 2 upload calls, got $(wc -l < "$UP_DIR/state/uploads.log")"
second="$(sed -n 2p "$UP_DIR/state/uploads.log")"
case " $second " in
  *" mongodump-amd64 "*) fail "the retry re-sent mongodump-amd64, which had already arrived" ;;
  *) ok "the retry sends only what did not arrive ($second)" ;;
esac
[ "$(wc -l < "$UP_DIR/state/assets" | tr -d ' ')" = 4 ] \
  && ok "every binary and its .sha256sum ends up on the release" \
  || fail "the release carries $(wc -l < "$UP_DIR/state/assets") of 4 files"

# NEGATIVE: an upload that never succeeds must FAIL the job, not pass quietly.
if run_upload 99; then
  fail "an upload that failed every attempt still succeeded"
else
  [ "$(wc -l < "$UP_DIR/state/uploads.log" | tr -d ' ')" = 3 ] \
    && ok "an upload that keeps failing fails the job after UPLOAD_ATTEMPTS tries" \
    || fail "it gave up after $(wc -l < "$UP_DIR/state/uploads.log") tries, not 3"
fi
# NEGATIVE: called with no files (an empty out/), it refuses rather than succeed.
if ( PATH="$GHBIN:$PATH" GH_STATE="$UP_DIR/state" \
     bash "$ROOT/.github/scripts/upload-release-assets.sh" v-test ) >/dev/null 2>&1; then
  fail "upload-release-assets.sh with no files succeeded"
else
  ok "with no files to upload it fails instead of reporting success"
fi

# ── 8. Moving source and dependency inputs stay explicit ─────────────────────
echo
# Resolving newer dependencies after local review would bypass the preflight.
echo "The workflows build the reviewed toolchain and dependency graph:"
for wf in "$ALL" "$MISSING"; do
  n="$(basename "$wf")"
  grep -q "go-version: '1.27.1'" "$wf" && ok "$n pins reviewed Go" \
    || fail "$n does not pin reviewed Go"
  grep -q 'releases/update-dependencies.sh' "$wf" && ok "$n restores reviewed dependencies" \
    || fail "$n does not restore dependencies"
  grep -q -- '--upstream-version' "$wf" && ok "$n checks upstream review" \
    || fail "$n does not check upstream review"
done
! grep -q 'go get -u' "$ROOT/releases/update-dependencies.sh" \
  && ok "release cannot upgrade the reviewed graph" \
  || fail "release still resolves unaudited dependencies"
grep -q 'reviewed-go/go.mod' "$ROOT/releases/update-dependencies.sh" \
  && ok "reviewed Go manifest restored" || fail "reviewed Go manifest missing"

python3 "$ROOT/tests/release-telemetry.py" && ok "binary telemetry gates" || fail "binary telemetry gates failed"

python3 "$ROOT/tests/telemetry-audit.py" && ok "telemetry source and vendor guards" \
  || fail "telemetry source and vendor guards failed"

python3 "$ROOT/tests/dragonfly-terminal.py" && ok "terminal platform constraints (Go required)" \
  || fail "terminal platform constraints failed"

echo
if [ "$fails" -eq 0 ]; then
  echo "workflow-logic: everything holds."
else
  echo "workflow-logic: $fails check(s) FAILED."
fi
exit $(( fails > 0 ))
