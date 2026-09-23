# Platforms

MongoDB Database Tools binaries built from upstream + these patches, at these
platforms:

- [Releases](https://github.com/wekan/mongo-tools-patches/releases)
- [Upstream mongo-tools](https://github.com/mongodb/mongo-tools)
- [How WeKan consumes them](https://github.com/wekan/wekan)
- [Design docs](docs/Design/Directory-structure.md)

Each build applies the patches onto a shallow, single-branch clone
(`--depth 1 --single-branch`) of current upstream `master`, including changes not
yet in a release. It then selects the newest stable Go, upgrades the complete module
graph and regenerates `vendor/`. What was current when this workflow was introduced:

| Upstream | Ref | Release identity | Commit |
|----------|-----|------------------|--------|
| [mongodb/mongo-tools](https://github.com/mongodb/mongo-tools) | `master` | `master-575cf6b` | [`575cf6b8431e9964cdf6d247ea301c1c64691f6a`](https://github.com/mongodb/mongo-tools/commit/575cf6b8431e9964cdf6d247ea301c1c64691f6a) |

Each release's own notes repeat this table for the exact version it carries, filled
in by the build from the ref and exact commit it cloned.

<details>
<summary>Version</summary>

- A moving ref never reuses a release. Its identity combines the ref with Git's short
  commit hash, for example `master-575cf6b`, while the full hash remains in every
  binary and its release notes.
- Source patches in `dist/all/` run after cloning; SDK patches in `dist/vendor/`
  run after dependency regeneration. Both apply to every target. See
  [dist/README.md](dist/README.md).
- Each patch is a `*.patch` file with a `*.sha256sum` (the checksum of the patch file)
  and a `*.md` (what the patch does). The build clones upstream at the selected ref,
  verifies each checksum, and applies the patch.
- The upstream commit, Go toolchain and module graph are resolved at build time, so
  source fixes and dependency updates do not wait for another upstream release.
- The binaries a release carries are named `<tool>-<arch>` (`<tool>-<arch>.exe` on
  Windows), each with a `.sha256sum`. A release accumulates binaries — a rebuilt one
  clobbers its own asset and leaves the rest alone.
- The eight tools: `bsondump`, `mongodump`, `mongoexport`, `mongofiles`,
  `mongoimport`, `mongorestore`, `mongostat`, `mongotop`.
- The forty-two platforms cover every native Go OS/CPU pair on which current
  mongo-tools compiles with CGO disabled: Linux, Windows, macOS, FreeBSD,
  NetBSD, OpenBSD, DragonFly BSD and AIX, including all buildable 32-bit ARM,
  MIPS and PowerPC variants. Shared `<arch>` tokens match
  wekan/FerretDB's `ferretdb-<arch>` naming.

</details>

# TODO Later

<details>
<summary>Carried to a future release.</summary>

Investigated but not finished, with findings recorded for whoever picks them up
next. Entries that have since been done are removed from this list as they are
handled (their commits carry the short description and link).

- No full build has run in the development sandbox — it has no Go toolchain — so the
  compile itself is covered by a stubbed `go` in `tests/workflow-logic.sh` and by the
  first CI run, not by a local build.

</details>

# Upcoming mongo-tools-patches release

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/8ed724c1ab5a6cf0a8504b66d19c152b8fbf2c56">Distinguish known dependency keyword false positives from new findings</a>. Thanks to xet7.</summary>

Report documented, exact dependency keyword matches as known false
positives for default outbound reporting. New or changed matches remain
unclassified warnings for review. Independent source and binary risk
checks remain active. Current dependency inventories have no matches
requiring new exemptions. Positive and negative launcher tests, risk
tests and offline audits pass across all six release repositories.
This changes release logs only; no application UI or hosted release
was exercised. Existing Upcoming regression coverage is retained.

</details>

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/62207c445449bbb826e7c06f166ad19ba8c900c6">Fix Windows release source paths and allow scoped version links</a>. Thanks to xet7.</summary>

Pass a shell-relative checkout path to the Node release resolver so
Git Bash does not receive a native Windows path. This fixes the shared
win64 and win-arm64 source-selection failure before compilation.
Optional per-file URL patterns permit explicitly configured version
links while other new hosts, paths and query strings still fail.
Offline positive and negative release and indicator tests pass; native
Windows builds and hosted publication were not run.

</details>

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/c5c5fc193726395fb656e14cd813be6bfa044cd9">Accept valid GitHub SSH origins in release launchers</a>. Thanks to xet7.</summary>

Release All and Release All Missing accept HTTPS and SSH clone URLs
with or without .git, including git@github.com:wekan/mongo-tools-patches.
Incorrect repositories and lookalike hosts still stop the release.
Offline positive and negative launcher tests and source audits pass;
no hosted release was run.

</details>

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/666c245">Add release menus and automated dependency checks</a>. Thanks to xet7.</summary>

Add shell and Windows Release All / Release All Missing menus. Full releases
validate Upcoming notes, prepare a source version, commit all pending files,
push and dispatch Actions. Missing builds retain the existing release tag and
skip complete binary/checksum pairs, replacing incomplete pairs together.

Dependency fingerprints are informational. Known hashes, new suspicious
keywords and new URL literals stop automated checks without requiring AI
approval or exhaustive review. Restore the locked Go graph before vendoring
and telemetry patching. Launcher/indicator tests, workflow tests, real vendor
regeneration and SDK checks pass; hosted publishing was not run.

</details>

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/8f10930">Reject telemetry in native release binaries</a>. Thanks to xet7.</summary>

Both release workflows retain source/vendor review and SDK request checks, and
now scan every compiled or retained output before checksumming. Source, patch
and binary failures show error messages; binary failures stop the matrix rather
than becoming unsupported-platform skips. Offline workflow and gate tests pass.
All eight patched native tools passed; a stripped binary built with the patch
reversed was rejected as a negative control.

</details>

**In short:** this repository replaces the source fork with a reproducible build from
current upstream **master**, including unreleased fixes. Every snapshot uses the
**newest stable Go**, upgrades and vendors the **complete dependency graph**, and gets
a commit-specific release identity. The shared workflows cross-compile the **eight
tools** for **forty-two platforms** without mixing binaries from different upstream
commits.

This release follows current upstream development:

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/8a34332">Remove cloud SDK reporting after vendoring and audit every source change</a>. Thanks to xet7.</summary>

The previous audit found no standalone tools usage reporter but missed dependency
reporting. Remove Azure/MSAL client identification headers and AWS SDK v1/v2
runtime, environment, feature and credential-source reporting implementations.
Apply the checksum-verified vendor patch after dependency regeneration so the
upgrade cannot restore it, and disable Go toolchain telemetry.

Both preparation and compilation now compare source and vendor inventories with
the reviewed tree. New upstream or dependency code stops the build for review,
including code without telemetry-related keywords. Keep the release asset list
outside audited source files. Authentication, database handshakes, cloud
operations, request correlation and local diagnostic hooks remain functional.

Verified upstream `5e7290222cae7ebd5eade59bc19d6f25b637a1d3` with refreshed
dependencies and Go 1.27.1: all eight tools compiled and ran `--version` on macOS
ARM64, five SDK packages passed request-path tests with fake transports, BSON
conversion passed, and offline workflow/patch/audit regression tests passed.
A fresh macOS ARM64 rebuild also passed startup/help checks for all eight tools
and database-connected import/export, dump/restore, BSON conversion, GridFS
put/get/delete, mongostat and mongotop checks against an isolated MongoDB server.
The source/vendor inventories and native telemetry gates passed, with no startup
errors. The full platform matrix, hosted releases and live cloud integrations
were not run.
See [the audit and update procedure](docs/Design/Telemetry-audit.md).

</details>

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/d341c92">Add the Android ARM64 command-line target</a>. Thanks to xet7.</summary>

The CGO-free upstream tools compile for Android arm64, expanding the canonical
registry to forty-three targets and 344 possible binaries. Other Android
architectures still require external CGO linking, while iOS and WebAssembly do
not produce equivalent standalone command-line programs. Tests keep target and
asset counts synchronized across full and missing-only releases.

</details>

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/4fa0b90">Allow the expanded tools matrix to finish</a>. Thanks to xet7.</summary>

Both full and missing-only workflows now allow three hours for the forty-two
target build instead of retaining the former seventeen-target one-hour limit.
The offline workflow test pins the timeout in both paths so adding platforms
cannot create a predictably cancelled release build.

</details>

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/18b9af9">Build every currently supported native Go target</a>. Thanks to xet7.</summary>

Release All expands from seventeen to forty-two OS/CPU targets after compiling
current upstream master with Go 1.27 across Go's native command-line platforms.
It adds AIX, DragonFly BSD, NetBSD and OpenBSD, all compiling FreeBSD CPUs, and
Linux MIPS and big-endian PowerPC. Illumos, Solaris and Plan 9 remain excluded
because current upstream source does not compile there; mobile and WebAssembly
ports are not native command-line release executables.

The canonical build script still skips and names any individual tool that a
future upstream change makes unbuildable. Its offline regression now verifies
eight tools times forty-two targets, all checksums and the release-repair path.
Temporary compiler diagnostics also stay inside the configured `.tools/tmp`
tree instead of the system temporary directory.

</details>

**Source and dependencies** - how unreleased fixes and current dependencies reach the
published binaries without losing provenance.

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/dbe8878">Each build follows upstream master and uses newest Go and dependencies</a>. Thanks to xet7.</summary>

The default source is upstream `master`, so fixes such as bounded archive-restore
concurrency, corrected connection-duration handling and more reliable oplog dump
checks are built without waiting for the next Database Tools tag. An explicit ref can
still reproduce an older source.

Every moving-ref build is isolated under `master-SHORT-COMMIT-HASH`; the full hash is
also embedded in the binaries and linked from the release notes. The workflows install
the newest stable Go, run `go get -u ./...`, tidy the complete module graph and
regenerate `vendor/` before compiling. The old fixed security-floor list and tracked
major file are removed because neither could provide newest-source semantics.

Offline workflow tests cover the default and overridden refs, the commit-derived
identity, both workflows' Go/dependency steps, patch integrity and every build target.
A real current-master preparation upgraded the module graph successfully, and focused
tests for common options, `mongodump` and `mongorestore` passed with Go 1.27.

</details>

and creates the repository:

**The build** - what clones upstream, what compiles, and what a release carries.

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/3291cd5">Release All builds every tool for every platform from upstream plus the patches</a>. Thanks to xet7.</summary>

One `workflow_dispatch` run checks the patches out into `_patches/`, clones the
newest upstream `100.x` release beside them, applies the patches, pins the Go
toolchain from the **upstream** `go.mod` (which is why `setup-go` runs after the
clone, not before), and cross-compiles the eight tools for the sixteen platforms into
`out/` with `CGO_ENABLED=0`.

It is ONE job, where wekan/node-patches needs fourteen: the tools are pure Go,
so every target is an ordinary `GOOS=… GOARCH=… go build` on the x86_64 runner —
no container, no cross toolchain, no emulation, minutes instead of the hours a V8
build takes. A target that does not compile is skipped and reported, never fatal, because
MongoDB itself ships no tools for several of these and an honest gap beats a red run.

The release notes carry the platform list, the three commands that verify a download,
a provenance table (upstream repo, branch, tag, exact commit) and upstream's own
CHANGELOG section for that version. Assets go up with
`--clobber`, so a release accumulates: a rebuilt binary overwrites only itself. The
release is tagged with the upstream version, because that is what it is — upstream at
that release plus the patches in `dist/`.

</details>

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/3291cd5">Release All Missing builds only the binaries a release does not already carry</a>. Thanks to xet7.</summary>

A release carries up to 128 assets — eight tools times sixteen platforms, each with a
`.sha256sum`. When one upload fails, or a platform is added, or a run is cancelled
half way, rebuilding all of them replaces bytes that were already correct. This asks
the release what it has and builds the gap.

A binary counts as present only when BOTH it and its `.sha256sum` are on the release,
so a binary whose checksum upload failed is repaired rather than left half published.
The upload runs without `--clobber`, because everything built here was absent: an
upload that would overwrite something means the release changed under the run, and
that is worth failing on. Nothing to build at all is a notice, not a failure.

It shares the scripts rather than calling Release All as a reusable workflow, which
is what node-patches has to do with its fourteen platform-specific jobs. Here
the build is one script, so sharing the script is enough — and it avoids the
caller/callee concurrency-group deadlock that indirection brought with it there.

</details>

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/3291cd5">The upstream release is resolved from a major line instead of being typed into a workflow</a>. Thanks to xet7.</summary>

`releases/newest-release.sh` reads `tools-major.txt` (`100`) and asks upstream for the
newest `100.<MINOR>.<PATCH>` release tag. "Release" means a published tag — never a
branch head, never a commit between releases — so a build is always of an upstream
release and is reproducible.

Two things make this different from node-patches' script of the same name: upstream
tags the Database Tools `100.17.0` with **no leading `v`**, and its tag list still
carries the old `r4.2.x` tags and release candidates, so the filter has to be strict
about what a release of this major looks like.

A new upstream patch release therefore needs no edit at all — the next run picks it
up. A new major is a one-line edit to `tools-major.txt`.

</details>

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/3291cd5">The clone, the checksum check and the patch apply are one script both workflows run</a>. Thanks to xet7.</summary>

`releases/apply-patches.sh` clones upstream at the resolved tag, moves the tree into
the workspace root beside the patches checkout, verifies each patch's `.sha256sum`
before applying it, and records the exact upstream commit — which is then stamped into
every binary's `--version` output, printed in the run summary and repeated in the
release notes, so a binary traces to the source it was built from.

The checksum is verified BEFORE `git apply`, so a corrupted or hand-edited patch fails
loudly instead of applying wrong, and a patch that no longer applies to the pristine
tag fails here too — which is the signal to re-port it.

The move is deliberately a single `mv` under `dotglob`. node-patches' first run added
a second, explicit `mv nodesrc/.git .` after it and killed all thirteen of its builds
three seconds after cloning, because the glob had already taken `.git`; `rmdir` then
asserts nothing was left behind, and a guard checks `.git` really arrived. The test
script fails if that second move ever comes back.

</details>

**The patches** - the section, and why there are none in it yet.

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/3291cd5">The fork this replaces changed no upstream source, so the patch section starts empty</a>. Thanks to xet7.</summary>

`wekan/mongo-tools` was a fork of a large Go project, and every one of its six commits
was the build workflow and its changelog. The Go source beside them was upstream's,
unmodified, kept in a fork only so a workflow had somewhere to live. That is exactly
the arrangement node-patches retired for Node.js.

So `dist/all/` is empty, and the build says so rather than hiding it: *"No patches in
dist/all - building pristine upstream 100.17.0."* It is where a patch goes the day a
tool needs one to compile for a platform upstream does not build, and
`build-tools.sh`'s list of targets it could not compile is the shopping list.

</details>

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/3291cd5">A patch for one platform carries a Go build constraint instead of a section of its own</a>. Thanks to xet7.</summary>

node-patches organises patches into six sections with an apply-map, because each of
its thirteen platforms is its own build job with its own checkout — so a patch can be
applied to the i386 tree and not to the arm64 one.

Here ONE checkout cross-compiles all sixteen targets, so there is no per-platform tree
to apply a patch to, and a patch that concerns one GOOS or GOARCH says so in Go
instead: `//go:build loong64`, a `_linux_386.go` filename, a `runtime.GOARCH` branch —
which is how upstream and every other Go project do it, and which the single patched
tree then compiles correctly for every target at once.

If a patch ever cannot be expressed that way, sections come back and the hook for them
is already there: the workspace is a real git clone, so the build can
`git checkout . && git clean -fd` between targets. That is a change to make when there
is a patch that needs it, not before.

</details>

**The tests and the documentation** - what can be checked without a runner, and what
the next reader is told.

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/3291cd5">workflow-logic.sh runs the repo's own scripts against a fixture upstream and a stubbed Go</a>. Thanks to xet7.</summary>

No network, a couple of seconds, and it does not restate the logic in a test and then
check the copy — the logic lives in scripts and this runs those scripts. It resolves
the newest release against a local fixture repository whose tags include an `rc`, an
`r4.2.x` and another major, so the filter is really exercised; it clones and patches
a fixture upstream through `apply-patches.sh`; and it runs `build-tools.sh` with a
stubbed `go` to check the target list, the skip list, the checksum files and what the
build treats as fatal.

Its negative tests are what make the rest mean anything: a patch whose checksum does
not match must not be applied, the `mv …/.git` bug must fail if it comes back, a
binary whose checksum is missing from the release must be rebuilt, and a build that
produced nothing at all must fail rather than publish an empty release.

</details>

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/3291cd5">patches-apply.sh applies every patch to the upstream release the build would clone</a>. Thanks to xet7.</summary>

The question this repo lives or dies on is whether its patches still apply, and the
answer otherwise arrives as a `git apply` error in a build log nobody is watching.

It does not clone mongo-tools — a large repository with its whole vendored dependency
tree, to answer a question about a handful of files. It reconstructs exactly the files
the patches touch, taken from their own headers so a patch that starts touching
another file is fetched without anyone remembering to add it, fetches them from
upstream at the tag the build's own resolver picked, and applies the patches
cumulatively, checksum first. It exits 77 when upstream is unreachable, so a sandbox
without network says so instead of reporting a green run it did not do.

</details>

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/3291cd5">The design docs, README and CLAUDE.md say what the repo is and how to change it</a>. Thanks to xet7.</summary>

`docs/Design/Directory-structure.md` is the layout, `How-the-build-works.md` the
clone→verify→apply→build→publish flow and what to do when upstream releases or a patch
stops applying, and `Patch-format.md` the three-file convention — `.patch`,
`.sha256sum`, `.md` — with where a patch comes from in the first place.

`CLAUDE.md` carries the maintainer/contributor rule, the changelog format and the
release step, as the WeKan repositories do. The licensing is stated in all three
places, because this repo mixes two: its own files (workflows, scripts, docs) are MIT,
while a patch in `dist/` is a modification of Apache-2.0 upstream source and stays
Apache-2.0, as do the binaries built from it.

</details>

and adds a seventeenth platform:

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/2d3d2cb">armv6 — GOARM=6, matching wekan/FerretDB's new target</a>. Thanks to xet7.</summary>

The arch tokens and the target set here are deliberately the same as
[wekan/FerretDB](https://github.com/wekan/FerretDB)'s `build.sh`, so that
`ferretdb-<arch>` and `mongodump-<arch>` line up and one token names a
platform's whole set — which is why armv6 is added on both sides at once, for
the ARMv6 WeKan bundle (Raspberry Pi 1 and Zero) that both of them feed.

`armel` is `GOARM=5` and would run on an ARMv6 board, which is what makes it
look like a substitute: it does floating point in software, while `GOARM=6` uses
the VFPv2 the hardware actually has. `armel` stays for genuine ARMv5.

</details>

and fixes what the first run turned up:

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/dbd75ef">The release is published to this repository, not to the upstream one the workspace points at</a>. Thanks to xet7.</summary>

The first run built all 128 binaries and then failed on the upload:

```
HTTP 403: Resource not accessible by integration
(https://api.github.com/repos/mongodb/mongo-tools/releases)
```

`gh` works out which repository to act on from the git remote of the working
directory - and by publish time the working directory IS the upstream clone,
because that is the whole arrangement here: the patches sit in `_patches/` and
upstream is moved to the workspace root so the build sees an ordinary
mongo-tools tree. Its origin is `mongodb/mongo-tools`, so `gh release create` was trying to
publish onto MongoDB's repository, which this token has no business writing to.

Every step that runs `gh` now sets `GH_REPO` to this repository. `gh` reads that
natively, so `release-assets.sh` is covered by the same setting instead of
growing a flag of its own - and its header says why it is not optional.

</details>

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/dbd75ef">Upstream's own release notes are taken from where they are actually written</a>. Thanks to xet7.</summary>

The same run warned that upstream's `CHANGELOG.md` has no 100.17.0 section, and
it was right: upstream tags the release and writes the entry AFTERWARDS. Tag
`100.17.0` is commit `0b142f65` ("100.17.0 release: BOM & SARIF files"), and the
entry arrived in `9cd3c4a8` ("TOOLS-4197 Update changelog for 100.17.0"), which
comes after it - so the notes carried the header and nothing else.

The lookup tries the tag first, because when the entry is there it is the
changelog of precisely the source that was built, and then the default branch,
which is where it actually is. Only when neither has it does the warning stand.

</details>

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/dbd75ef">Guards for both, including the notes extractor run against a fixture changelog</a>. Thanks to xet7.</summary>

`tests/workflow-logic.sh` now checks that every workflow step carrying a
`GH_TOKEN` also carries a `GH_REPO` - a step with the one and not the other is
the 403 above - and that the notes lookup names a fallback ref at all. The
extraction itself is not restated in the test: the workflow's own `awk` program
is lifted out and run against a fixture `CHANGELOG.md` with three sections, to
show it takes the version's own section and stops at the next one rather than
running on into the neighbouring release.

</details>

and documents how to work on this repository:

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/320ae6d">AGENTS.md — what a contributor, human or otherwise, has to know before touching a patch</a>. Thanks to xet7.</summary>

A patches-only repository is unusual enough that the obvious first move is the
wrong one: there is no mongo-tools source here to edit, so a change is a change
to a `.patch` file, and it has to apply to a tag nobody has cloned yet.
`AGENTS.md` writes that down — what the patches are for, that they are applied
to the newest upstream RELEASE tag rather than a branch head, how to verify one
applies before pushing, and which workflow builds the binaries WeKan embeds.

</details>

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/9e0f847">Every place that counts the targets says seventeen, and the test expects the binaries armv6 adds</a>. Thanks to xet7.</summary>

Adding armv6 above made the target count wrong everywhere it was written out:
`AGENTS.md`, `CLAUDE.md`, `dist/README.md`, both design docs and both workflows
said sixteen platforms, and the release-capacity number that follows from it —
eight tools times the targets — said 128 where it is now 136.

`tests/workflow-logic.sh` was not merely stale, it was **failing**: it runs the
real `build-tools.sh` against a stubbed `go` and asserts the binary count, which
armv6 moved from 127 to 135 (one target is stubbed to fail on purpose, and that
part still holds). The expected number moves with the target list rather than
the check being loosened, and the comment beside it says why it changed, so the
next reader sees a decision instead of a suspicious edit.

Left alone on purpose: *"the first run built all 128 binaries and then failed on
the upload"*. That is what that run built.

</details>

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/f0da894">The maintainer rules move to WeKan's CLAUDE.md and AGENTS.md, and the copies here are removed</a>. Thanks to xet7.</summary>

`CLAUDE.md` and `AGENTS.md` here said who maintains this repository, who commits
and as whom, and how the CHANGELOG is written. Every word of that is true of each
repository WeKan clones into its `.tools/` directory and none of it is specific
to this one, so it was a second copy of a rule — and a second copy drifts. WeKan's
own `CLAUDE.md` and `AGENTS.md` now carry the rules for all of them, including
the layout of `.tools/` and the instruction not to add these files back here.

What was genuinely about THIS repository was already elsewhere and stays:
`docs/Design/Directory-structure.md` and `docs/Design/How-the-build-works.md` for
the layout and the build, `dist/README.md` for the one section and why it is
empty, and each test script's own header for what it checks. The design doc and
the README point at WeKan's files for the rules, so a reader who starts here
still finds them.

</details>

Thanks to above GitHub users for their contributions.

and raises what the published binaries are built with:

**The security floor** - what a scan reads out of the finished binaries, and how
the build keeps it from going backwards.

<details>
<summary><a href="https://github.com/wekan/mongo-tools-patches/commit/cd1277c">The toolchain and the vendored dependencies are raised to a floor before the tools are compiled</a>. Thanks to xet7.</summary>

A container scan of `ghcr.io/wekan/wekan:v10.91` reads every binary in the
image, and the nine tools this repository publishes each reported the same 37
findings, because they are the same build:

| What | The binaries carried | Fixed in |
| --- | --- | --- |
| Go toolchain (`stdlib`) | 1.25.9 | 1.25.12 |
| `golang.org/x/crypto` | 0.45.0 | 0.52.0 |
| `golang.org/x/net` | 0.47.0 | 0.56.0 |
| `golang.org/x/text` | 0.31.0 | 0.39.0 |
| `golang.org/x/sys` | 0.38.0 | 0.44.0 |

None of that is a patch that was missed. A release is vendored at the moment it
is cut and the advisories arrive afterwards, and those versions are simply what
upstream 100.17.0 vendored: the toolchain comes from upstream's `go.mod`, which
is exactly why `setup-go` runs after the clone, and `x/crypto` and the rest
come out of upstream's `vendor/`. **Building the newest upstream release is what
fixes them** - 100.18.0 builds with Go 1.26.5 and vendors `x/crypto` 0.54.0,
`x/net` 0.56.0, `x/text` 0.40.0 and `x/sys` 0.47.0, every one above the line
above - and the version resolution already takes the newest `100.x`, so a
rebuild is the fix.

What this adds is that the fix cannot be undone by accident.
[`releases/security-minimums.txt`](releases/security-minimums.txt) is a FLOOR,
and `releases/security-bumps.sh` applies it in the two places it has to be
applied: `toolchain` rewrites the `go` line **before** `setup-go` reads it,
since that is what decides which Go is installed and therefore what `stdlib`
says in the finished binary, and `vendor` runs **after** it, because `go get`,
`go mod tidy` and `go mod vendor` are go commands. A module upstream vendored at
or above its line is left alone and says so; nothing is ever dragged backwards.
On 100.18.0 the whole step is a no-op, which is the intended outcome - it earns
its place on a build pinned to an older tag with `version-override`, and on the
next advisory that lands under a release already vendored below it.

A `.patch` could not do this. `vendor/` is thousands of files, and a patch
against it would stop applying at the next upstream release; re-resolving keeps
working as upstream moves.

</details>
