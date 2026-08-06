# CLAUDE.md — instructions Claude reads first

Claude Code reads this file at the repo root before doing work here. Follow it.

This repository (github.com/wekan/mongo-tools-patches) carries **only patches** to the
upstream MongoDB Database Tools — no mongo-tools source. It is modelled on
[wekan/node-patches](https://github.com/wekan/node-patches) and, in turn, on
[Betterbird/thunderbird-patches](https://github.com/Betterbird/thunderbird-patches):
CI clones upstream at a release tag, applies the patches, and publishes the built
binaries. WeKan embeds those binaries. The old `wekan/mongo-tools` source fork is
retired in favour of this repo — it changed nothing in upstream's Go source, it only
carried the build — so a change that used to be a commit on the fork is now either a
patch here or a change to the build here.

## First: are you the maintainer or a contributor?

Check the current git identity before committing:

```
git config user.name && git config user.email
```

- **Maintainer mode** — ONLY when the identity is exactly
  `Lauri Ojansivu <x@xet7.org>`. Then, and only then: commit **directly to the
  current branch** as `Lauri Ojansivu <x@xet7.org>` with no AI trailer and no pull
  request, and the release step below is available. Per the standing rule you still
  **commit only; do not push** unless explicitly asked.
- **Contributor mode** — any other git identity. Then: do **not** commit directly and
  do **not** run the release step. Make changes on a branch and open a **pull
  request** for the maintainer to review.

## What is in this repo

```
mongo-tools-patches/
  CHANGELOG.md                 wekan-style changelog (see below)
  CLAUDE.md                    this file
  tools-major.txt              the Database Tools major line to track (100)
  .github/
    workflows/
      release-all.yml          clone upstream, apply patches, build every tool for
                               every platform, publish
      release-all-missing.yml  build only the binaries a release does not yet carry
    scripts/
      build-tools.sh           THE build: targets, ldflags, per-binary checksums
      release-assets.sh        what a release already carries
  releases/
    newest-release.sh          resolve the newest upstream <MAJOR>.x release
    apply-patches.sh           clone upstream at that tag and apply dist/
  tests/
    workflow-logic.sh          offline: runs the repo's own scripts
    patches-apply.sh           network: applies every patch to upstream
  dist/
    README.md                  the section, and why there is only one
    all/                       applied to every target
      <name>.patch             the code patch (git apply / git format-patch style)
      <name>.sha256sum         sha256 of <name>.patch, checked before applying
      <name>.md                what the patch does, wekan-changelog style
  docs/Design/                 how the repo is laid out and how the build works
```

See [docs/Design/Directory-structure.md](docs/Design/Directory-structure.md) for the
full layout, [dist/README.md](dist/README.md) for the section, and
[docs/Design/How-the-build-works.md](docs/Design/How-the-build-works.md) for the
clone→verify→apply→build→publish flow.

## Working on the patches

There are **no patches today**, and that is the honest state: upstream compiles for
every platform WeKan ships, so the repo is upstream plus a build. `dist/` is where a
patch goes the day a tool stops compiling for a platform — `build-tools.sh` reports
every target it could not compile, and that report is the shopping list. The rules:

- **One patch = three files** with the same base name: `<name>.patch`,
  `<name>.sha256sum`, `<name>.md`. All three are required; the build fails on a
  `.patch` without a matching `.sha256sum` (the checksum is verified before the patch
  is applied), and the `.md` documents it for the changelog and the next reader.
- **There is one section, `dist/all/`, and a per-platform patch says so in Go.** One
  checkout here cross-compiles all sixteen targets, so a patch cannot be applied to
  one platform's tree only; a change that concerns one GOOS or GOARCH carries a build
  constraint (`//go:build loong64`, a `_linux_386.go` filename, a `runtime.GOARCH`
  branch). [dist/README.md](dist/README.md) says what would bring sections back and
  where the hook for them already is.
- **Prefer a patch upstream would take.** Anything portable belongs in a
  [mongodb/mongo-tools](https://github.com/mongodb/mongo-tools) pull request first;
  the patch here carries it until upstream ships it, and its `.md` links the PR so the
  patch can be dropped when it lands.
- **Generate a patch** from a source tree that has upstream at the tag as its base:
  `git diff 100.17.0..HEAD -- <paths>` (or `git format-patch`). Keep each patch
  applying cleanly to a **pristine upstream checkout** — that is what CI applies it
  to; `./tests/patches-apply.sh` checks exactly that.
- **Recompute the checksum whenever the patch changes:**
  `sha256sum <name>.patch > <name>.sha256sum` (run it in `dist/all` so the file
  records the bare name, which is how CI checks it). A stale checksum fails the build.
- **Write the `.md` in wekan-changelog style:** a `# <name>` title, a one-line
  summary, the body (what was wrong, what it does now), then `**Files:**`,
  `**Platforms:**` and `**Applies to:**`. It is the source for the CHANGELOG entry.
- **A new upstream release needs nothing** — the build already targets the newest
  `<MAJOR>.x` release. Only re-port a patch if `git apply` fails on the newer release.
  A new **major** is a one-line edit to `tools-major.txt`, then re-verify and re-port.

Fix from source and verify — do not guess. If this environment cannot run a full
build, say clearly what was and was not verified.

## Tests

Two scripts, and both run here:

- `./tests/workflow-logic.sh` — no network, a couple of seconds. It RUNS the repo's
  own scripts rather than restating them: it resolves the newest release against a
  local fixture repository (so the `rc`, `r4.2.x` and other-major tags are really
  filtered), clones and patches a fixture upstream through
  `releases/apply-patches.sh`, and runs `.github/scripts/build-tools.sh` with a
  stubbed `go` to check the target list, the skip list, the checksums and what it
  treats as fatal. It carries the negative tests that make the rest meaningful: a
  wrong checksum must not be applied, the sibling repo's `mv …/.git` bug must fail if
  it comes back, a half-published binary must be rebuilt, and a build that produced
  nothing at all must fail. Run it after ANY change to a script or a workflow.
- `./tests/patches-apply.sh [version]` — needs the network. It reconstructs the files
  the patches touch from upstream at the resolved release and `git apply`s them,
  checksum first, the same way the build does. It does not clone mongo-tools, and
  exits 77 when upstream is unreachable, so a sandbox with no network says so instead
  of reporting a green run it did not do.

A full build needs Go and a runner; neither test pretends to be one. What they cover
is the class of failure that kills a run in its first seconds.

## CHANGELOG

`CHANGELOG.md` uses the **same formatting as the WeKan repo's CHANGELOG** — read that
file for the canonical rules; the shape here is identical, only the subject differs.
In short:

- The file's shape, top to bottom: `# Platforms` (the links block and a `<details>`
  summarised `Version`), then `# TODO Later` (a `<details>` per category of things
  investigated but not done), then the releases newest first, each
  `# v<x> YYYY-MM-DD mongo-tools-patches release`. Nothing else is an `#` heading — a
  `##` inside a release, or a wrapped line beginning with `#`, would become one;
  escape a leading `#NNNN` as `\#NNNN`.
- During development, add entries under a new `# Upcoming mongo-tools-patches release`
  section above the newest release. Do **not** hand-edit version references — the
  release step bumps those.
- The Upcoming section opens with an `**In short:**` paragraph summarising the whole
  release, notable names in `**bold**`.
- Every entry is a `<details>` block whose `<summary>` is on ONE line, ≤110 chars,
  plain text (no links/bold/backticks inside `<summary>`), ending with a full stop
  then `Thanks to …`. The commit hash lives in the `href`, never as link text. A blank
  line under the summary, the word-wrapped-at-80 body, a blank line, the close, and a
  blank line between blocks.
- Multi-entry subsections are **grouped by area** with a `**Area** - description.`
  label line (on ONE physical line, ending in a period) above each group; every entry
  under it drops the area prefix. A single-entry subsection stays flat.
- Subsection headers read as one flowing sentence: the first starts with
  `This release `, every later one with a lowercase `and `. The release ends with
  `Thanks to above GitHub users for their contributions.`
- Word-wrap at 80 chars, but never break a link across lines. Never show a long URL as
  visible text — `[#NNNN](…)`, `[short text](url)`.

There is no translation workflow in this repo — that section of the WeKan CLAUDE.md
does not apply here.

## Commit message structure

```
Do something.

Thanks to (original creator of issue, if any) and xet7 !

Fixes #1234,
```

Commit as `Lauri Ojansivu <x@xet7.org>` (maintainer only), with **no**
"Co-Authored-By" or any other AI trailer, directly to `main`. **Do not make pull
requests** (contributors do the opposite). **Commit only. Do not push** unless
explicitly asked.

## Making a release  **[maintainer only]**

- Run **Release All** (`.github/workflows/release-all.yml`, `workflow_dispatch`) with
  no `version` input to build the newest upstream `<MAJOR>.x` release (from
  `tools-major.txt`), or `-f version=100.17.0` to pin one. It clones upstream at that
  release tag, verifies+applies the patches, cross-compiles the eight tools for the
  sixteen platforms, and uploads each `<tool>-<arch>[.exe]` and its `.sha256sum` to a
  release tagged with the **upstream version**, accumulating (a rebuilt binary
  clobbers only its own asset).
- Run **Release All Missing** to fill in only what a release does not yet carry — it
  asks the release what it has and builds the rest. Use it when an upload failed, a
  run was cancelled, or a platform was added after the others were published.
- The publishing steps are **maintainer-only**. Contributors never run them.

## Licensing

This repository's own files — workflows, scripts, docs, changelog — are MIT
([LICENSE](LICENSE)). Upstream mongo-tools is **Apache-2.0**, so a `.patch` in `dist/`
is a modification of Apache-2.0 source and stays Apache-2.0, as do the binaries CI
builds. Do not relicense upstream's work, and do not copy upstream source files into
this repo — a patch, not a copy, is the whole point.

## Environment

The editor (VSCode) runs inside a Flatpak sandbox (see the WeKan repo's
`docs/Security/Sandboxes/vscode/README.md`). A full Go build of the tools does not run
in the sandbox; verify with the two test scripts and say what was and was not
verified.

### Always validate from the actual code

When doing anything, check how it actually works in the scripts and the workflows
first.
