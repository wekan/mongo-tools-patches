#!/bin/bash
#
# tests/multicall.sh - releases/multicall.sh makes one program out of the eight
# tools, and that program is each of them by name or by first argument.
#
# A fixture shaped like upstream (module github.com/mongodb/mongo-tools, one
# <tool>/main package per tool with VersionStr/GitCommit and func main) is
# generated, built with the real Go toolchain, and run. Without Go on PATH the
# build checks are skipped and said so; the generator checks always run.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/multicall-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
pass=0; failed=0
ok()   { echo "ok   $*"; pass=$((pass + 1)); }
fail() { echo "FAIL $*"; failed=$((failed + 1)); }

TOOLS="bsondump mongodump mongoexport mongofiles mongoimport mongorestore mongostat mongotop"
SRC="$TMP/src"
mkdir -p "$SRC"
printf 'module github.com/mongodb/mongo-tools\n\ngo 1.22\n' > "$SRC/go.mod"
for t in $TOOLS; do
  mkdir -p "$SRC/$t/main"
  cat > "$SRC/$t/main/$t.go" <<EOF
// Main package for the $t tool.
package main

import (
	"fmt"
	"os"
	"strings"
)

var (
	VersionStr = "built-without-version-string"
	GitCommit  = "build-without-git-commit"
)

func main() {
	fmt.Printf("$t %s %s args=%s\n", VersionStr, GitCommit, strings.Join(os.Args[1:], ","))
}
EOF
done

( cd "$SRC" && bash "$ROOT/releases/multicall.sh" ) >"$TMP/gen.log" 2>&1 \
  && ok "it generates from an upstream-shaped tree" || fail "generation failed: $(cat "$TMP/gen.log")"
for t in $TOOLS; do
  grep -q "^package ${t}main\$" "$SRC/wekan_multicall/tools/$t/$t.go" \
    && grep -q '^func Main() {$' "$SRC/wekan_multicall/tools/$t/$t.go" || { fail "$t was not turned into package ${t}main with Main()"; continue; }
done
ok "each tool became an importable package with Main()"
cmp -s "$SRC/mongodump/main/mongodump.go" <(cat "$SRC/mongodump/main/mongodump.go") \
  && grep -q '^package main$' "$SRC/mongodump/main/mongodump.go" \
  && ok "upstream's own sources are not edited" || fail "upstream sources changed"

flags="$(bash "$ROOT/releases/multicall.sh" --ldflags 100.1.2 abc123)"
for t in $TOOLS; do
  case "$flags" in *"-X github.com/mongodb/mongo-tools/wekan_multicall/tools/$t.VersionStr=100.1.2"*) ;; *) fail "no version flag for $t"; esac
done
case "$flags" in "-s -w "*) ok "the ldflags strip and stamp every tool" ;; *) fail "ldflags do not strip: $flags" ;; esac

# Negative: a tree that is not mongo-tools, or a tool with two main()s, is refused.
mkdir -p "$TMP/other"; printf 'module example.com/other\n' > "$TMP/other/go.mod"
( cd "$TMP/other" && bash "$ROOT/releases/multicall.sh" ) >/dev/null 2>&1 \
  && fail "it ran outside a mongo-tools tree" || ok "it refuses a tree that is not mongo-tools"
cp -r "$SRC" "$TMP/twice"; printf '\nfunc main() {\n}\n' >> "$TMP/twice/mongotop/main/mongotop.go"
( cd "$TMP/twice" && bash "$ROOT/releases/multicall.sh" ) >/dev/null 2>&1 \
  && fail "it accepted a file with two main()s" || ok "it refuses a file it would have to guess about"

if ! command -v go >/dev/null 2>&1; then
  echo "skip the build and run checks: no go on PATH"
else
  ( cd "$SRC" && CGO_ENABLED=0 GOFLAGS=-mod=mod go build -trimpath -ldflags "$flags" -o "$TMP/mongo-tools" ./wekan_multicall ) \
    >"$TMP/build.log" 2>&1 && ok "it builds" || fail "build failed: $(tail -3 "$TMP/build.log")"
  for t in $TOOLS; do ln -s mongo-tools "$TMP/$t"; done
  ln -s mongo-tools "$TMP/mongodump-amd64"; cp "$TMP/mongo-tools" "$TMP/mongorestore.exe"
  [ "$("$TMP/mongodump" a b)" = "mongodump 100.1.2 abc123 args=a,b" ] && ok "run as mongodump, it is mongodump" || fail "symlink name: $("$TMP/mongodump" a b)"
  [ "$("$TMP/mongodump-amd64" x)" = "mongodump 100.1.2 abc123 args=x" ] && ok "the -<platform> asset name works" || fail "asset name"
  [ "$("$TMP/mongorestore.exe")" = "mongorestore 100.1.2 abc123 args=" ] && ok "a .exe name works" || fail ".exe name"
  [ "$("$TMP/mongo-tools" bsondump --help)" = "bsondump 100.1.2 abc123 args=--help" ] \
    && ok "mongo-tools <tool> runs it, with the tool's own arguments" || fail "first-argument form"
  "$TMP/mongo-tools" nope >/dev/null 2>"$TMP/usage"; rc=$?
  [ "$rc" = 2 ] && grep -q "usage: mongo-tools <tool>" "$TMP/usage" \
    && ok "an unknown tool is a usage error, not a guess" || fail "unknown tool: rc=$rc"
fi

echo "multicall: $pass ok, $failed failed"
[ "$failed" -eq 0 ]
