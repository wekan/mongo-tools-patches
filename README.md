# mongo-tools-patches

Patches to the upstream [MongoDB Database Tools](https://github.com/mongodb/mongo-tools)
100.x, and the build that makes the `<tool>-<arch>` binaries WeKan ships in every
bundle, Docker image and snap.

This repository carries **no mongo-tools source**. Each build clones the newest
upstream `100.x` release, verifies and applies the patches in
[`dist/`](dist/README.md), cross-compiles the eight tools (`bsondump`, `mongodump`,
`mongoexport`, `mongofiles`, `mongoimport`, `mongorestore`, `mongostat`, `mongotop`)
for every platform with CGO disabled, and publishes one binary per tool per platform
with a `.sha256sum` beside each. It replaces the `wekan/mongo-tools` source fork,
which carried no source change of its own — only this build. Same model as
[wekan/node-patches](https://github.com/wekan/node-patches).

- [Releases](https://github.com/wekan/mongo-tools-patches/releases)
- [Directory structure](docs/Design/Directory-structure.md)
- [How the build works](docs/Design/How-the-build-works.md)
- [Patch format](docs/Design/Patch-format.md)

This repository's own files (workflows, scripts, docs) are MIT — see
[LICENSE](LICENSE). Upstream mongo-tools is Apache-2.0, and a patch in `dist/` is a
modification of that source: it, and the binaries built from it, stay Apache-2.0.
