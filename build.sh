#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
command="${1:-}"
if [ -z "$command" ]; then
  printf '1) Release All
2) Release All Missing
0) Exit
Selection: '
  read -r choice
  case "$choice" in 1) command=release-all;; 2) command=release-all-missing;; 0) exit 0;; *) echo 'Invalid selection' >&2; exit 2;; esac
else
  shift
fi
case "$command" in
  release-all|release-all-missing) exec bash "$root/releases/$command.sh" "$@" ;;
  *) echo "Usage: $0 [release-all|release-all-missing] [--check] [version]" >&2; exit 2 ;;
esac
