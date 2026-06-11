#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# const: flat series - ATR 0, RSI 50 (no gains, no losses)
jq -n '[range(0;60) | {t: ., o:100, h:100, l:100, c:100, v:1000}]' > /tmp/bars-const.json
# ramp: +1/day; h spike at bar 45 sits just OUTSIDE the 14-bar ATR window (pins
# the window: a 15-bar bug would include it); volume spike on the last bar pins
# the relvol baseline exclusion (a baseline including the current bar reads 2.73)
jq -n '[range(0;60) | {t: ., o:(100+.), h:(if .==45 then (103+.) else (101+.) end), l:(99+.), c:(100+.), v:(if .==59 then 3000 else 1000 end)}]' > /tmp/bars-ramp.json
# desc: -1/day - pins the RSI=0 branch (all losses, no gains)
jq -n '[range(0;60) | {t: ., o:(159-.), h:(160-.), l:(158-.), c:(159-.), v:1000}]' > /tmp/bars-desc.json
C=$(jq -r -L scripts/lib 'include "indicators"; indicators | @tsv' /tmp/bars-const.json)
R=$(jq -r -L scripts/lib 'include "indicators"; indicators | @tsv' /tmp/bars-ramp.json)
D=$(jq -r -L scripts/lib 'include "indicators"; indicators | @tsv' /tmp/bars-desc.json)
# columns: last_close atr14 rsi14 sma20 sma50 relvol a1 a2
[ "$C" = "$(printf '100\t0\t50\t100\t100\t1\t100\t100')" ]    || { echo "FAIL const: [$C]"; exit 1; }
[ "$R" = "$(printf '159\t2\t100\t149.5\t134.5\t3\t152\t124')" ] || { echo "FAIL ramp: [$R]"; exit 1; }
[ "$D" = "$(printf '100\t2\t0\t109.5\t124.5\t1\t99\t99')" ]   || { echo "FAIL desc: [$D]"; exit 1; }
echo "PASS test-indicators"
