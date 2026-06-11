#!/usr/bin/env bash
# Live network smoke test - run manually, not part of run-tests.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(scripts/indicators.sh "NVDA,XCHP.TO")
echo "$OUT"
[ "$(echo "$OUT" | wc -l | tr -d ' ')" = "3" ] || { echo "FAIL: expected header + 2 rows"; exit 1; }
echo "$OUT" | tail -2 | awk -F'\t' 'NF != 9 { print "FAIL: row with " NF " cols"; exit 1 }'
echo "PASS smoke-indicators"
