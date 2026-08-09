# How the build works

This repo carries no mongo-tools source. The build reconstructs the source at run
time: **clone upstream → verify → apply patches → build → publish**. Two workflows do
it, and both run the same two scripts.

## Release All (`.github/workflows/release-all.yml`)

A `workflow_dispatch` that builds one upstream Database Tools version for every
platform and uploads the binaries to that version's GitHub Release.

1. **Check out the patches** into `_patches/` (`actions/checkout`), keeping this
   repo's files separate from the mongo-tools tree about to be created.
2. **Pick the version, clone upstream, apply the patches** —
   `releases/apply-patches.sh _patches "<version input>"`:
   ```sh
   V="$(releases/newest-release.sh _patches "$OVERRIDE")"   # newest 100.x release tag
   git clone --depth 1 --single-branch --branch "$V" \
     https://github.com/mongodb/mongo-tools.git toolssrc
   COMMIT="$(git -C toolssrc rev-parse HEAD)"   # the exact bytes built from
   shopt -s dotglob; mv toolssrc/* .; rmdir toolssrc
   for p in _patches/dist/all/*.patch; do
     ( cd _patches/dist/all && sha256sum -c "$(basename "${p%.patch}").sha256sum" )
     git apply "$p"
   done
   ```
   `--branch "$V"` is the one release tag, `--single-branch` fetches that ref and no
   other head, `--depth 1` takes only the tag's commit — so the clone is the newest
   `100.x` release and nothing else. The checksum is verified **before** the patch is
   applied: a corrupted or hand-edited patch fails the build loudly instead of being
   applied wrong, and a patch that no longer applies to the pristine tag fails here
   too, which is the signal to re-port it. `$COMMIT` goes into the run summary, the
   release notes and the binaries' own `--version` output, so every binary traces to
   the upstream source it was built from.
3. **Pin the toolchain** — `actions/setup-go` with `go-version-file: go.mod`, run
   **after** the clone, because that `go.mod` is upstream's: the Go version the build
   uses is the one the release being built asks for.
4. **Build** — `.github/scripts/build-tools.sh`. Eight tools × seventeen targets, each
   a `CGO_ENABLED=0 GOOS=… GOARCH=… go build -trimpath -ldflags "…"`, into `out/`.
   No containers, no cross toolchains, no emulation: pure Go cross-compiles from the
   ordinary x86_64 runner, which is why one job covers every platform and finishes in
   minutes. A target that does not compile is **skipped and reported, never fatal** —
   MongoDB itself ships no tools for several of these, and an honest gap beats a red
   run. Every binary gets a `<name>.sha256sum` beside it.
5. **Publish.** The notes carry the platform list, the checksum-verification
   commands, and a **provenance table** — upstream repo, `<MAJOR>.x` branch, tag,
   exact commit — followed by upstream's own CHANGELOG section for that version,
   fetched from the tag. Assets go up with `gh release upload --clobber`, so a
   release **accumulates**: a rebuilt binary overwrites only itself and everything
   else stays. The release is tagged with the **upstream version** (`100.17.0`),
   because that is what it is: upstream at that release plus the patches in `dist/`.

## Release All Missing (`.github/workflows/release-all-missing.yml`)

A release carries up to 136 assets. Rebuilding all of them to obtain the one whose
upload failed replaces bytes that were already correct, so this builds the gap:

1. **Ask the release what it has** — `.github/scripts/release-assets.sh`.
2. **Build what is absent** — the same `build-tools.sh`, with `SKIP_LIST=existing.txt`.
   A tool counts as present only when BOTH its binary and its `.sha256sum` are on the
   release, so a half-published binary is rebuilt rather than left broken.
3. **Upload without `--clobber`**, because everything built here was absent: an
   upload that would overwrite something means the release changed under the run, and
   that is worth failing on.

Nothing to build at all is a **notice, not a failure** — it means the release is
complete.

There is no second copy of the target list, the ldflags or the apply loop in either
workflow: both call the same two scripts. (node-patches instead calls its
`release-all.yml` as a reusable workflow, because its build is thirteen
platform-specific jobs. Here one script is the whole build, so sharing the script is
enough — and it avoids the caller/callee concurrency-group deadlock that indirection
brought with it there.)

## Keeping up with upstream releases

Nothing to do for a new upstream release of the same major: the build already targets
the newest `<MAJOR>.x` release, so when upstream ships 100.18.0 the next run clones
and builds it — no version to type, no directory to add. Only if a patch no longer
applies does the build fail, at the `git apply` step, which is the signal to re-port
that one patch: clone upstream at the failing tag, fix the patch, regenerate it,
recompute its `.sha256sum`, update its `.md`, and add a CHANGELOG entry.

## Moving to a new major line

1. Edit `tools-major.txt` (e.g. `100` → `101`).
2. Clone upstream at the new line's newest release and verify every patch still
   applies (`./tests/patches-apply.sh`); re-port what does not.
3. Recompute the changed `.sha256sum`s, update the `.md`s, add a CHANGELOG entry, and
   run **Release All** (no `version` → the newest release of the new major).

## What WeKan does with the result

WeKan's own release build downloads `<tool>-<arch>` and its `.sha256sum` from this
repo's releases and embeds the binaries in every bundle, Docker image and snap —
`bsondump`, `mongodump`, `mongorestore` and the rest are what its backup and restore
paths call. The `<arch>` tokens match `wekan/FerretDB`'s `ferretdb-<arch>` naming, so
one token names the whole set for a platform.
