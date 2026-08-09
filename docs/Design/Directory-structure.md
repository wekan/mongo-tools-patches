# Directory structure

`mongo-tools-patches` carries **only patches** to the upstream MongoDB Database
Tools, never their source. The binaries WeKan embeds are built by CI, which clones
upstream at a release tag, applies the patches here, builds, and publishes. This is
the same model as [wekan/node-patches](https://github.com/wekan/node-patches) and, in
turn, as [Betterbird/thunderbird-patches](https://github.com/Betterbird/thunderbird-patches).

```
mongo-tools-patches/
├── CHANGELOG.md                       Release notes, WeKan-changelog format.
├── CLAUDE.md                          Maintainer/contributor rules for this repo.
├── tools-major.txt                    The Database Tools major line to track (100).
├── .github/
│   ├── workflows/
│   │   ├── release-all.yml            Clone upstream → verify+apply patches →
│   │   │                              cross-compile 8 tools × 17 platforms →
│   │   │                              publish to the release.
│   │   └── release-all-missing.yml    Build only the binaries a release lacks,
│   │                                  through the same scripts.
│   └── scripts/
│       ├── build-tools.sh             The build: the target list, the ldflags,
│       │                              the per-binary checksums. Used by BOTH
│       │                              workflows, so they cannot drift.
│       └── release-assets.sh          What a release already carries.
├── releases/
│   ├── newest-release.sh              Resolve the newest upstream <MAJOR>.x release.
│   └── apply-patches.sh               Clone upstream at that tag and apply dist/.
├── dist/
│   ├── README.md                      The section, and why there is only one.
│   └── all/                           Applied to every target. Empty today.
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

One section, `all/`, applied to the single checkout that cross-compiles every
target. A patch that concerns one GOOS or GOARCH carries a Go build constraint
rather than living in a platform directory — see [`dist/README.md`](../../dist/README.md)
for why that differs from node-patches, and what would bring sections back.

Every patch is **three files sharing a base name**:

| File | What it is |
|------|-----------|
| `<name>.patch` | The code change, as `git diff` / `git format-patch` output, applying cleanly to a pristine upstream checkout of the tracked release. |
| `<name>.sha256sum` | `sha256sum <name>.patch`, run in the section directory so it records the bare name. CI verifies this **before** applying the patch, so a corrupted or edited patch fails loudly instead of applying wrong. |
| `<name>.md` | What the patch does — a `# <name>` title, one-line summary, body, `**Files:**`, `**Platforms:**`, `**Applies to:**`. The source for the CHANGELOG entry and the next reader's explanation. |

## `tools-major.txt` — which upstream line to track

A one-line file naming the Database Tools major (`100`). The build reads it, then
resolves the **newest upstream `<MAJOR>.x` release** — a published tag, never a branch
head or a commit between releases. Upstream tags carry no leading `v` (`100.17.0`),
which is the one difference between this repo's `newest-release.sh` and
node-patches'. Bumping to a new major is a one-line edit.

## `.github/` and `releases/` — the build

`release-all.yml` builds everything; `release-all-missing.yml` builds only what a
release lacks. Neither carries the build itself: the clone+apply is
`releases/apply-patches.sh` and the compile is `.github/scripts/build-tools.sh`, so
the two workflows run the identical code and a binary added to a release months later
is built exactly like the ones beside it. See
[How-the-build-works.md](How-the-build-works.md).

## What is NOT here

- **No mongo-tools source.** It is cloned from `github.com/mongodb/mongo-tools` at
  the release tag each build. The retired `wekan/mongo-tools` fork held that source
  and changed none of it.
- **No version directories.** The upstream version is resolved at build time from
  `tools-major.txt`.
- **No built binaries in git.** They live on the GitHub Releases of this repo, one
  set per version, named `<tool>-<arch>` / `<tool>-<arch>.exe` with a
  `<tool>-<arch>.sha256sum` each.
- **No Go module of its own.** Nothing here is compiled; `go.mod` comes from the
  upstream clone, and it is what pins the toolchain the build uses.

## Licensing

The files in this repository — workflows, scripts, docs, changelog — are MIT, as
[`LICENSE`](../../LICENSE) says. The upstream MongoDB Database Tools are
**Apache-2.0**, and a `.patch` in `dist/` is a modification of that Apache-2.0 source:
it stays under Apache-2.0, as do the binaries CI builds, which are upstream's code
with the patches applied. Nothing here relicenses upstream's work.
