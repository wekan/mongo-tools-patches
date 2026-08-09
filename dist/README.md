# dist/ — the patch section

Patches to upstream `mongodb/mongo-tools`, applied to a **shallow clone of the
newest upstream `<MAJOR>.x` release** (`MAJOR` from
[`../tools-major.txt`](../tools-major.txt)) before every build. Nothing here is
organised by upstream version: the version is resolved at build time, so a patch
carries forward across upstream releases until the day it stops applying.

## There is one section, `all/`

| Section | Applies to | What it carries |
|---------|-----------|-----------------|
| `all/` | every target | Everything. |

`wekan/node-patches` has six sections and an apply-map, because each of its
thirteen platforms is **its own build job with its own checkout** — so a patch can
be applied to the i386 tree and not to the arm64 one. Here **one checkout
cross-compiles all seventeen targets** (pure Go, `CGO_ENABLED=0`, one
`GOOS=… GOARCH=… go build` per target), so there is no per-platform tree to apply
a patch to. A patch that concerns one platform says so **in Go**, with a build
constraint:

```go
//go:build loong64
```

which is how upstream and every other Go project do it, and which the single
patched tree then compiles correctly for every target at once.

If a patch ever genuinely cannot be expressed with a build constraint — a `go.mod`
change needed by one GOARCH only, say — sections come back, and the hook for them
is already there: the workspace is a real git clone, so `build-tools.sh` can
`git checkout . && git clean -fd` between targets and apply a different set. Do
that when there is a patch that needs it, not before.

## There are no patches today, and that is the point

The `wekan/mongo-tools` fork this repo replaces carried **no source changes at
all** — six commits, every one of them the build workflow and its changelog. The
738 directories of Go source beside them were upstream's, unmodified, kept in a
fork only so a workflow had somewhere to live. That is exactly the arrangement
`wekan/node-patches` retired for Node.js, and this repo retires it here.

So `dist/` starts empty. It is where a patch goes the day a tool needs one to
compile for a platform upstream does not build — `build-tools.sh` reports each
target it could not compile, and that report is the shopping list.

## Each patch is three files

Every patch is `<name>.patch`, `<name>.sha256sum` (checksum of the `.patch`,
verified before it is applied) and `<name>.md` (what it does). See
[../docs/Design/Patch-format.md](../docs/Design/Patch-format.md).
