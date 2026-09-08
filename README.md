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

There is no telemetry code to remove here. Unlike
[wekan/mongosh-patches](https://github.com/wekan/mongosh-patches) (which patches out
mongosh's beacon reporting) and this fork's [FerretDB](https://github.com/wekan/FerretDB)
(which patches out its own beacon reporting), the eight MongoDB Database Tools built
here have no analytics client, no phone-home reporter, and no `--telemetry`/`DO_NOT_TRACK`
flag of their own — checked directly against upstream `mongodb/mongo-tools` source, not
assumed. The only match for "telemetry" anywhere in the tree is the vendored Azure SDK's
`policy_telemetry.go`, which is a `User-Agent` string builder for the tools' optional Azure
Key Vault / KMS calls (identifying the client library to Azure's own API, the same way
every HTTP client sends a `User-Agent`), not a usage-data collector, and it is
third-party vendored code this repository does not patch. **This fork has telemetry code
removed everywhere it exists to remove** — mongosh and FerretDB — **and mongo-tools has
none in the first place.**

This repository's own files (workflows, scripts, docs) are MIT — see
[LICENSE](LICENSE). Upstream mongo-tools is Apache-2.0, and a patch in `dist/` is a
modification of that source: it, and the binaries built from it, stay Apache-2.0.

Maintainer and contributor rules — who commits, as whom, and how the CHANGELOG is
written — are in [WeKan's CLAUDE.md and AGENTS.md](https://github.com/wekan/wekan),
which cover every repository WeKan clones into its `.tools/` directory.
