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

## Automated indicators for new code

Source/vendor hash differences are informational. The source checker then runs
`releases/risk-audit.py` against its upstream baseline: known telemetry/security
hashes, new suspicious keywords or new URL literals stop builds. Ordinary source
or dependency changes do not require an AI approval or a complete manual review.
Binary telemetry signatures and SDK behavior tests remain enforced.

Release builds restore the locked module graph, regenerate vendor and apply the
SDK telemetry patches. Update module files when needed; the automated indicator
checks, rather than hash differences alone, decide whether to stop. See
[release checks and baseline configuration](../../releases/README-release.md).

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

## Native artifact gate

Both release workflows now scan each successful native output before counting it
as built or writing checksums. A matching removed SDK implementation or reporting
endpoint emits `::error::Telemetry audit failed` and exits the entire matrix;
it cannot be classified as an unsupported target. Source audit failures use the
same log annotation. The workflow fixture tests this fatal path with a deliberately
contaminated compiler output. All eight local native executables passed.

This scan detects known implementation/endpoint signatures even in stripped Go
binaries, but is not proof that arbitrary encoded machine code cannot transmit
data. Retain source/vendor review and the SDK request tests alongside it.
