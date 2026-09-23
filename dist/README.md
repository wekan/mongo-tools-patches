# dist/ — shared patch stages

Both sections apply to every build target. A platform-specific fix uses Go build
constraints rather than a separate checkout.

| Section | Applied when | Purpose |
|---------|--------------|---------|
| `all/` | After cloning upstream | Tool source fixes |
| `vendor/` | After dependency upgrades and `go mod vendor` | Dependency changes, including SDK telemetry removal |

Vendored patches must run after regeneration or their changes are overwritten.
`releases/update-dependencies.sh` invokes `releases/apply-vendor-patches.sh`,
which verifies checksums, applies strict patches, and audits the resulting source
and vendor trees. New or changed code requires review before the build proceeds.

Every patch is `<name>.patch`, `<name>.sha256sum` (checksum of the patch), and
`<name>.md` (what it does). See [the patch format](../docs/Design/Patch-format.md).
