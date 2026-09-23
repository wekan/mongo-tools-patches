# Telemetry audit

The reviewed source is mongodb/mongo-tools commit
`5e7290222cae7ebd5eade59bc19d6f25b637a1d3`, with the complete dependency graph
refreshed using Go 1.27.1. The exact module graph is covered by the inventory in
`releases/telemetry-audit.json`.

No standalone usage reporter was found in the tools' own source. The previous
audit nevertheless missed automatic reporting in cloud SDK requests:

| Dependency | Removed behavior |
| --- | --- |
| Azure azcore 1.23.1 | SDK, application, Go runtime and OS identification in User-Agent |
| MSAL Go 1.9.0 | x-client-SKU, version, OS and CPU headers, including managed identity requests |
| AWS SDK Go v2 1.47.0 | User-Agent collection and transmission of SDK/runtime/platform, execution environment, features and credential-source identifiers |
| AWS SDK Go v1 1.55.8 | Default and custom User-Agent collection/transmission handlers |

The patch removes the implementations and retained reporting state while keeping
inert API entry points required by callers. It applies **after** `go mod vendor`;
applying it earlier would let the dependency refresh restore the removed code.
Go build/test commands set `GOTELEMETRY=off`.

Normal database handshakes, authentication, cloud API requests, request correlation
IDs, local logs, and user-requested database statistics remain. S3 Analytics APIs
are cloud operations, not a tools usage reporter. SDK metrics/tracing interfaces
and their default no-op implementations are not standalone telemetry exporters.
This audit does not claim that all network traffic or every diagnostic API is
removed.

## Guard against new code

After applying the patch, and again before compilation, the build compares every
source and vendor file's path and content with the reviewed inventory. This
includes dependency metadata and embedded resources, rather than relying on a
list of telemetry-related words. Added, changed, deleted and symlinked files
require review. Only root build metadata/output directories (`.git`, `.tools`,
`_patches`, `out`, `__pycache__`) are excluded; nested directories with these
names remain covered. Release asset lists live under `.tools`.

The workflows still resolve current upstream and upgrade dependencies. A changed
tree deliberately stops before building until reviewed. Do not automatically
refresh the inventory or loosen it to make a new upstream version pass. Review
source and dependency changes, update the patch and fixtures as needed, run the
SDK and tool checks, then record the resulting inventory in the same reviewed
change. To calculate an inventory after review, call `snapshot(source_directory)`
from `releases/audit-telemetry.py`; retain the reviewed upstream commit and Go
version alongside its `trees` result.

## Validation

- `bash tests/workflow-logic.sh` tests the real build scripts with local fixtures
  and a compiler stub, including rejection of source drift.
- `python3 tests/telemetry-audit.py` tests patch integrity, incompatible dependency
  rejection, and source/vendor additions, changes, deletions and symlinks.
- `bash tests/sdk-telemetry.sh /path/to/prepared/source` exercises actual SDK
  request paths using local fake transports. It verifies removed reporting
  headers and retained request forwarding, authentication and metadata.
- `bash tests/no-telemetry-upstream.sh --source /path/to/prepared/source` verifies
  an existing tree. Without `--source`, it fetches upstream and refreshes, patches
  and tests dependencies using the installed Go toolchain.

All eight tools compiled with CGO disabled and ran `--version` on macOS ARM64
using Go 1.27.1. The SDK tests passed for all five tested packages. The full
platform matrix was checked with a compiler stub, not cross-compiled in this
audit. Live MongoDB, AWS and Azure integration tests were not run.
