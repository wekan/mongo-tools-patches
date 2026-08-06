# Patch format

Patches live in `dist/all/`, the one section — see
[Directory-structure.md](Directory-structure.md) and
[`dist/README.md`](../../dist/README.md) for why there is only one, and what a
per-platform patch does instead.

Every patch is **three files sharing a base name**. The base name is the logical
change, kebab-case: `mongostat-loong64-build`, `gopsutil-riscv64-syscall`. All three
files are required — the build fails on a `.patch` without a matching `.sha256sum`.

```
dist/all/
  mongostat-loong64-build.patch       the code change
  mongostat-loong64-build.sha256sum   sha256 of the .patch, verified before applying
  mongostat-loong64-build.md          what the patch does
```

## `<name>.patch`

The code change, as `git diff` or `git format-patch` output, applying cleanly with
`git apply` to a **pristine upstream checkout** of the tracked release. That is what
CI applies it to, so verify it there — `./tests/patches-apply.sh` does exactly that
against the release the build would clone.

- **Group by logical change, not by file.** One patch may touch several files if they
  are one change; name it for what it does, not for a file.
- **Generate from a tree based on the upstream tag.** With upstream at the tag as the
  base of a working branch, `git diff 100.17.0..HEAD -- <paths>` is the patch.
- **A patch that only concerns one platform carries a Go build constraint**
  (`//go:build loong64`, a `_linux_386.go` filename, a `runtime.GOARCH` branch) rather
  than being applied selectively — one checkout here builds every target, so the tree
  must compile for all of them. Say which platform it is for in the `.md`.
- **Prefer a patch upstream would take.** Anything portable belongs in a
  [mongodb/mongo-tools](https://github.com/mongodb/mongo-tools) pull request first; a
  patch here is what carries it until upstream ships it, and the `.md` should link the
  PR so the patch can be dropped when it lands.
- **`vendor/` is fair game.** mongo-tools vendors its dependencies in-tree, so a fix
  to a dependency that has no upstream release yet is a patch to `vendor/…` — note in
  the `.md` that it must be re-checked whenever upstream re-vendors.

## `<name>.sha256sum`

```sh
cd dist/all && sha256sum mongostat-loong64-build.patch > mongostat-loong64-build.sha256sum
```

Run it **in the section directory** so the file records the bare name
(`<hash>  mongostat-loong64-build.patch`), which is how CI checks it (`sha256sum -c`).
Recompute it **whenever the patch changes** — a stale checksum fails the build, which
is the point: it makes a silently-edited patch impossible.

## `<name>.md`

What the patch does, in the WeKan CHANGELOG style, so it can be lifted into
`CHANGELOG.md`:

```markdown
# mongostat-loong64-build

One-line summary of what the patch fixes.

The body: what was wrong upstream, why, and what the patch does now — as much detail
as the change deserves, word-wrapped at 80. Link upstream issues/PRs as
[mongodb/mongo-tools#NNN](https://github.com/mongodb/mongo-tools/pull/NNN).

**Files:** `path/one`, `path/two`
**Platforms:** loong64 (guarded by `//go:build loong64`).
**Applies to:** upstream MongoDB Database Tools 100.x (verified against `100.17.0`).
```

The `**Platforms:**` line names the platforms it reaches and the build constraint that
keeps it off the others; the `**Applies to:**` line names the upstream version the
patch is verified against — update it when re-porting to a newer release or major.

## Where a patch comes from

`build-tools.sh` reports every target it could not compile:

```
  skipped mongostat-loong64 (does not compile)
          ...the last two lines of the compiler's own output...
```

That report is the shopping list. A tool that fails to build for a platform WeKan
ships a bundle for is what a patch here is for; a tool nobody needs on that platform
can stay skipped, and the log says so honestly either way.
