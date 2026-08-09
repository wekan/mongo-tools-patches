# Platforms

MongoDB Database Tools binaries built from upstream + these patches, at these
platforms:

- [Releases](https://github.com/wekan/mongo-tools-patches/releases)
- [Upstream mongo-tools](https://github.com/mongodb/mongo-tools)
- [How WeKan consumes them](https://github.com/wekan/wekan)
- [Design docs](docs/Design/Directory-structure.md)

Each build applies the patches onto a **shallow, single-branch** clone
(`--depth 1 --single-branch`) of the newest upstream MongoDB Database Tools
**release** — the newest `<MAJOR>.x` tag (`MAJOR` from
[`tools-major.txt`](tools-major.txt)), never a branch head or a commit between
releases, and with no git history behind the tag. What was cloned for the current
line:

| Upstream | Branch | Tag | Commit |
|----------|--------|-----|--------|
| [mongodb/mongo-tools](https://github.com/mongodb/mongo-tools) | 100.x | [100.17.0](https://github.com/mongodb/mongo-tools/releases/tag/100.17.0) | [`0b142f65e139525881b6a343bc56d8d98e5a1f90`](https://github.com/mongodb/mongo-tools/commit/0b142f65e139525881b6a343bc56d8d98e5a1f90) |

Each release's own notes repeat this table for the exact version it carries, filled
in by the build from the tag it cloned.

<details>
<summary>Version</summary>

- Upstream tags the Database Tools `100.17.0` — no leading `v`, unlike Node.js — and
  its tag list still carries the old `r4.2.x` ones, so the version resolution takes
  the newest `<MAJOR>.<MINOR>.<PATCH>` of the tracked major and nothing else.
- There is ONE patch section, `dist/all/`, applied to every target. One checkout
  cross-compiles all seventeen platforms here, so a patch that concerns one GOOS
  or GOARCH carries a Go build constraint rather than a section of its own. See
  [dist/README.md](dist/README.md).
- Each patch is a `*.patch` file with a `*.sha256sum` (the checksum of the patch file)
  and a `*.md` (what the patch does). The build clones upstream at the release tag,
  verifies each checksum, and applies the patch.
- The upstream version is resolved at build time — the newest `<MAJOR>.x` release — so
  the patches carry forward across upstream releases without editing.
- The binaries a release carries are named `<tool>-<arch>` (`<tool>-<arch>.exe` on
  Windows), each with a `.sha256sum`. A release accumulates binaries — a rebuilt one
  clobbers its own asset and leaves the rest alone.
- The eight tools: `bsondump`, `mongodump`, `mongoexport`, `mongofiles`,
  `mongoimport`, `mongorestore`, `mongostat`, `mongotop`.
- The seventeen platforms: `amd64`, `arm64`, `armhf`, `armv6`, `armel`, `i386`,
  `ppc64le`, `s390x`, `riscv64`, `loong64`, `win64`, `win-arm64`, `win32`,
  `mac-amd64`, `mac-arm64`, `freebsd-amd64`, `freebsd-arm64`. The `<arch>`
  tokens match wekan/FerretDB's `ferretdb-<arch>` naming, so one token names a
  platform's whole set.

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

**In short:** the repository that replaces the **wekan/mongo-tools** source fork. That
fork held 738 directories of upstream Go source it never changed — its six commits
were all the **build** — so this repo keeps the build and drops the source: **Release
All** and **Release All Missing** clone the newest upstream `100.x` release, verify
and apply the patches in **`dist/`**, cross-compile the **eight tools** for
**seventeen platforms** with CGO disabled, and publish one `<tool>-<arch>`
binary and `.sha256sum` per platform. Same model as **wekan/node-patches**, with
the one difference the language forces: pure Go cross-compiles from a single
checkout, so there is one patch section instead of six and one build job instead
of fourteen.
Below that: the two scripts both workflows share so they cannot drift, the two **test
scripts** that run the real code offline against a fixture upstream and a stubbed Go,
and the design docs and maintainer instructions the repo is set up with.

This release creates the repository:

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
