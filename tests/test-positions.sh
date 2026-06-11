#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(scripts/positions.sh tests/fixtures/trades-sample.json)
expect() {
  echo "$OUT" | grep -qxF "$(printf '%b' "$1")" || { echo "FAIL missing: $1"; echo "--- got:"; echo "$OUT"; exit 1; }
}
expect 'MU\tibkr-usd\tUSD\t10\t850\t1000\t820\t1000\topen'
expect 'XCHP\ttfsa-cad\tCAD\t100\t130\t0\t-\t-\topen'
expect 'DRAM\tibkr-usd\tUSD\t0\t55\t100\t-\t-\tclosed'
expect 'AVGO\tibkr-usd\tUSD\t3\t101.33\t0\t-\t-\topen'
[ "$(echo "$OUT" | wc -l | tr -d ' ')" -eq 4 ] || { echo "FAIL: expected 4 rows, got:"; echo "$OUT"; exit 1; }

# negative paths: guards must fail loudly, empty journal must be valid
jq '.trades += [{"id":"2026-06-03-003","date":"2026-06-03","ticker":"MU","side":"sell","qty":999,"price":900,"currency":"USD","account":"ibkr-usd","setup":"other"}]' \
  tests/fixtures/trades-sample.json > /tmp/oversell.json
scripts/positions.sh /tmp/oversell.json 2>/dev/null && { echo "FAIL: mid-stream oversell not rejected"; exit 1; }
jq '.trades[0].qty = 0' tests/fixtures/trades-sample.json > /tmp/zeroqty.json
scripts/positions.sh /tmp/zeroqty.json 2>/dev/null && { echo "FAIL: zero qty not rejected"; exit 1; }
echo '{"trades":[]}' > /tmp/empty.json
EMPTY_OUT=$(scripts/positions.sh /tmp/empty.json)
[ -z "$EMPTY_OUT" ] || { echo "FAIL: empty journal produced rows"; exit 1; }
echo '{}' > /tmp/nokey.json
scripts/positions.sh /tmp/nokey.json 2>/dev/null && { echo "FAIL: missing .trades not rejected"; exit 1; }
echo "PASS test-positions"
