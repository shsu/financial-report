#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(scripts/positions.sh tests/fixtures/trades-sample.json)
expect() {
  echo "$OUT" | grep -qF "$(printf '%b' "$1")" || { echo "FAIL missing: $1"; echo "--- got:"; echo "$OUT"; exit 1; }
}
expect 'MU\tibkr-usd\tUSD\t10\t850\t1000\t820\t1000\topen'
expect 'XCHP\ttfsa-cad\tCAD\t100\t130\t0\t-\t-\topen'
expect 'DRAM\tibkr-usd\tUSD\t0\t55\t100\t-\t-\tclosed'
[ "$(echo "$OUT" | wc -l | tr -d ' ')" -eq 3 ] || { echo "FAIL: expected 3 rows, got:"; echo "$OUT"; exit 1; }
echo "PASS test-positions"
