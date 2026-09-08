#!/bin/bash
# End-to-end: build a bundle and run scripts/verify.sh against it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$ROOT/scripts/build.sh" --output "$TMP/v.app" >/dev/null
"$ROOT/scripts/verify.sh" "$TMP/v.app"
