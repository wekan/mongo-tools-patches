# Directory structure

`mongo-tools-patches` carries **only patches** to the upstream MongoDB Database
Tools, never their source. The binaries WeKan embeds are built by CI, which clones
upstream at current `master`, applies the patches here, upgrades the Go module graph,
builds, and publishes. This is
the same model as [wekan/node-patches](https://github.com/wekan/node-patches) and, in
turn, as [Betterbird/thunderbird-patches](https://github.com/Betterbird/thunderbird-patches).

The maintainer and contributor rules for this repository — who commits, as whom,
and how the CHANGELOG is written — live in
[WeKan's CLAUDE.md and AGENTS.md](https://github.com/wekan/wekan), which cover
every repository WeKan clones into its `.tools/` directory. There is no second
copy of them here.

```
mongo-tools-patches/
├── CHANGELOG.md                       Release notes, in the format this file's own
│                                      existing entries use.
├── .github/
│   ├── workflows/
│   │   ├── release-all.yml            Clone upstream → verify+apply patches →
│   │   │                              cross-compile 8 tools × 43 platforms →
│   │   │                              publish to the release.
│   │   └── release-all-missing.yml    Build only the binaries a release lacks,
│   │                                  through the same scripts.
│   └── scripts/
│       ├── build-tools.sh             The build: the target list, the ldflags,
│       │                              the per-binary checksums. Used by BOTH
│       │                              workflows, so they cannot drift.
│       └── release-assets.sh          What a release already carries.
├── releases/
│   ├── newest-release.sh              Resolve the upstream ref (master by default).
│   ├── apply-patches.sh               Clone that ref and apply dist/all/.
│   ├── update-dependencies.sh         Upgrade, vendor, patch and audit the module graph.
│   ├── apply-vendor-patches.sh        Apply dist/vendor/ after dependency refresh.
│   ├── audit-telemetry.py             Reject source and dependency drift.
│   └── telemetry-audit.json           Reviewed tree inventory.
├── dist/
│   ├── README.md                      The two application stages.
│   ├── all/                           Source patches for every target.
│   └── vendor/                        SDK reporting removal after vendoring.
├── docs/
│   └── Design/
│       ├── Directory-structure.md     This file.
│       ├── How-the-build-works.md     The clone→verify→apply→build→publish flow.
│       └── Patch-format.md            The three-file convention and how to author it.
└── tests/
    ├── workflow-logic.sh              Offline: runs the repo's own scripts.
    └── patches-apply.sh               Network: applies every patch to upstream.
```

## `dist/` — the patches

Two stages apply to every target: `all/` after cloning upstream and
`vendor/` after refreshing dependencies. Platform-specific changes use Go build
constraints. See [dist/README.md](../../dist/README.md) and the
[telemetry audit](Telemetry-audit.md).

Every patch is **three files sharing a base name**:

| File | What it is |
|------|-----------|
| `<name>.patch` | The code change, as `git diff` / `git format-patch` output, applying cleanly at its documented source or regenerated-vendor stage. |
| `<name>.sha256sum` | `sha256sum <name>.patch`, run in the section directory so it records the bare name. CI verifies this **before** applying the patch, so a corrupted or edited patch fails loudly instead of applying wrong. |
| `<name>.md` | What the patch does — a `# <name>` title, one-line summary, body, `**Files:**`, `**Platforms:**`, `**Applies to:**`. The source for the CHANGELOG entry and the next reader's explanation. |

## `.github/` and `releases/` — the build

`release-all.yml` builds everything; `release-all-missing.yml` builds only what a
release lacks. Neither carries the build itself: the clone+apply is
`releases/apply-patches.sh` and the compile is `.github/scripts/build-tools.sh`, so
the two workflows run the identical code and a binary added to a release months later
is built exactly like the ones beside it. Moving refs use commit-specific release
tags such as `master-575cf6b`, so snapshots never mix. See
[How-the-build-works.md](How-the-build-works.md).

## What is NOT here

- **No mongo-tools source.** It is cloned from `github.com/mongodb/mongo-tools` at
  current `master` (or an explicitly requested ref) each build. The retired fork held that source
  and changed none of it.
- **No version directories.** The exact upstream commit is resolved at build time.
- **No built binaries in git.** They live on the GitHub Releases of this repo, one
  set per version, named `<tool>-<arch>` / `<tool>-<arch>.exe` with a
  `<tool>-<arch>.sha256sum` each.
- **No Go module of its own.** The SDK regression tests compile against the prepared source; `go.mod` comes from the
  upstream clone and is upgraded and re-vendored during the build.

## Licensing

The files in this repository — workflows, scripts, docs, changelog — are MIT, as
[`LICENSE`](../../LICENSE) says. The upstream MongoDB Database Tools are
**Apache-2.0**, and a `.patch` in `dist/` is a modification of that Apache-2.0 source:
it stays under Apache-2.0, as do the binaries CI builds, which are upstream's code
with the patches applied. Vendored SDK fixtures and their patches retain their own MIT or Apache-2.0 licenses, supplied beside the fixtures. Nothing here relicenses upstream's work.
