#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build/module-cache"
xcrun swiftc "$ROOT/source/QuotaService.swift" "$ROOT/tests/QuotaServiceTests.swift" \
  -module-cache-path "$ROOT/build/module-cache" -o "$ROOT/build/QuotaServiceTests"
"$ROOT/build/QuotaServiceTests"
