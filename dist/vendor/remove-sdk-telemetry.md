# Remove cloud SDK identification and feature reporting

The tools have no standalone usage reporter, but their vendored cloud SDKs add
runtime, OS, architecture, environment and feature/credential-source information
to HTTP requests. Remove those builders and reporting state, leaving inert
compatibility middleware and ordinary request/authentication behavior.

The patch covers Azure azcore's telemetry policy, MSAL's x-client-* headers,
AWS SDK v2 user-agent feature reporting and AWS SDK v1 user-agent handlers.
It does not remove request correlation IDs, authentication metadata, MongoDB
protocol handshakes, S3 operations or local diagnostic hooks.

Apply after `go mod vendor`, not before dependency regeneration. Every target
uses the same patched vendor tree. An incompatible patch or changed reviewed
source/vendor inventory stops the build. The Go toolchain also runs with
`GOTELEMETRY=off` during dependency updates, tests and builds.

Verified against upstream commit `5e7290222cae7ebd5eade59bc19d6f25b637a1d3` with
dependencies refreshed using Go 1.27.1. Offline fixtures cover patch application,
checksums and refusal on unexpected source changes. SDK tests exercise request
forwarding and absence of reporting headers with in-process transports; all eight
tools compile for macOS ARM64. See [the audit](../../docs/Design/Telemetry-audit.md).
