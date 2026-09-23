# mongo-tools-patches

Patches to the upstream [MongoDB Database Tools](https://github.com/mongodb/mongo-tools)
development branch, and the build that makes the `<tool>-<arch>` binaries WeKan ships
in every
bundle, Docker image and snap.

This repository carries **no mongo-tools source**. Each build clones current upstream
`master`, including unreleased fixes, verifies and applies the patches in
[`dist/`](dist/README.md), cross-compiles the eight tools (`bsondump`, `mongodump`,
`mongoexport`, `mongofiles`, `mongoimport`, `mongorestore`, `mongostat`, `mongotop`)
for every platform with CGO disabled, upgrades all dependencies with the newest stable
Go, and publishes one binary per tool per platform with a `.sha256sum` beside each. It
replaces the `wekan/mongo-tools` source fork,
which carried no source change of its own — only this build. Same model as
[wekan/node-patches](https://github.com/wekan/node-patches).

The forty-three targets span every native Go OS/CPU pair on which current
mongo-tools compiles without CGO: Linux, Windows, macOS, FreeBSD, NetBSD,
OpenBSD, DragonFly BSD, AIX and Android ARM64, including 32-bit ARM, MIPS and
PowerPC variants.

- [Releases](https://github.com/wekan/mongo-tools-patches/releases)
- [Directory structure](docs/Design/Directory-structure.md)
- [How the build works](docs/Design/How-the-build-works.md)
- [Patch format](docs/Design/Patch-format.md)

## Telemetry

The eight tools have no standalone usage reporter in the reviewed upstream
source. Their cloud dependencies did contain reporting code: Azure/MSAL added
client and OS identification headers, and AWS SDKs reported runtime, environment,
features and credential-source information with requests. The checksum-verified
`dist/vendor/remove-sdk-telemetry.patch` removes those implementations.

Vendor patches run **after** dependency regeneration, so `go mod vendor` cannot
erase the removal. Both dependency preparation and compilation audit the reviewed
source and vendor inventories; added or changed code stops the build for review.
SDK tests verify request forwarding and absence of reporting headers. Go runs with
`GOTELEMETRY=off` during dependency updates, tests and builds.

Authentication, request correlation, database handshakes, S3 operations and local
diagnostic hooks remain. Those are ordinary database/cloud functionality, not a
background usage reporter. See [the telemetry audit](docs/Design/Telemetry-audit.md)
for the reviewed revision, verification and update procedure.

This repository's own files (workflows, scripts, docs) are MIT — see
[LICENSE](LICENSE). Upstream mongo-tools is Apache-2.0, and a patch in `dist/` is a
modification of its upstream source. SDK patches and test fixtures retain their
respective MIT or Apache-2.0 licenses; the tools remain Apache-2.0.

Maintainer and contributor rules — who commits, as whom, and how the CHANGELOG is
written — are in [WeKan's CLAUDE.md and AGENTS.md](https://github.com/wekan/wekan),
which cover every repository WeKan clones into its `.tools/` directory.
