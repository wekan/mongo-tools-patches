#!/usr/bin/env bash
# Upgrade the complete upstream module graph to the newest compatible versions
# and regenerate vendor/. Run after actions/setup-go has installed the newest
# stable Go release.
set -euo pipefail

CURRENT_GO="$(go env GOVERSION)"
CURRENT_GO="${CURRENT_GO#go}"

# Record the toolchain used by the build. The go directive is updated as well,
# so dependency selection and a later local build use the same language level.
go mod edit -go="$CURRENT_GO"

# ./... names every package in mongo-tools; -u upgrades their direct and
# transitive module dependencies. Tidy drops dependencies no longer reachable,
# and vendor makes the exact resolved graph the one compiled into every binary.
GOFLAGS=-mod=mod go get -u ./...
GOFLAGS=-mod=mod go mod tidy
GOFLAGS=-mod=mod go mod vendor

echo "Updated the complete module graph and vendor tree with Go ${CURRENT_GO}."
