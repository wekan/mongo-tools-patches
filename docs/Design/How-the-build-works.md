# How the build works

This repository carries no mongo-tools source. Both release workflows use the same
pipeline:

1. Check this repository out into `_patches/`.
2. Clone current upstream `mongodb/mongo-tools` `master` with `--depth 1` and
   `--single-branch`. An optional workflow input may select another branch or tag.
3. Record the full upstream commit and form the release identity from the ref and
   Git's short hash, for example `master-575cf6b`.
4. Verify every patch checksum and apply `dist/all/*.patch` in name order.
5. Install the newest stable Go release. Run `go get -u ./...`, `go mod tidy`, and
   `go mod vendor`, ensuring every reachable direct and transitive dependency is
   upgraded and the exact compiled graph is vendored.
6. Cross-compile all eight tools for all forty-three targets with CGO disabled. A
   target that cannot compile is reported and skipped; a run where nothing compiles
   fails.
7. Publish each binary and its SHA256 file to the commit-specific release.

The target registry covers native command-line binaries that current upstream
source actually compiles: Linux, Windows, macOS, FreeBSD, NetBSD, OpenBSD,
DragonFly BSD, AIX and Android ARM64. A Go 1.27 compile probe excludes Illumos and Solaris
(missing password terminal implementation) and Plan 9 (missing Unix signal
semantics). Other Android architectures require external CGO linking; iOS and
WebAssembly are not standalone command-line releases.

The full upstream commit is embedded in the tools and shown in the release notes.
Using a commit-specific release tag prevents a later `master` build from mixing its
binaries with an earlier snapshot.

## Release All Missing

The fill-in workflow resolves the same source identity, asks that release which
assets already exist, and builds only binaries lacking either the executable or its
checksum. Uploads do not use `--clobber`; an unexpected existing asset is a race and
fails instead of replacing bytes from another run.

## Keeping current

No version bump is required. Every default run starts at the current upstream
`master`, then independently selects the newest stable Go and newest compatible
module versions. If a local patch stops applying, `tests/patches-apply.sh` identifies
it so it can be re-ported.

## What WeKan consumes

WeKan downloads `<tool>-<arch>` and `<tool>-<arch>.sha256sum` from the newest release
and embeds the tools in its bundles, Docker image and snap. The `<arch>` tokens match
the FerretDB binary names.
