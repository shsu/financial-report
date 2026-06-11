#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
jq -n '[range(0;60) | {t: ., o:100, h:100, l:100, c:100, v:1000}]' > /tmp/bars-const.json
jq -n '[range(0;60) | {t: ., o:(100+.), h:(101+.), l:(99+.), c:(100+.), v:1000}]' > /tmp/bars-ramp.json
C=$(jq -r -L scripts/lib 'include "indicators"; indicators | @tsv' /tmp/bars-const.json)
R=$(jq -r -L scripts/lib 'include "indicators"; indicators | @tsv' /tmp/bars-ramp.json)
# columns: last_close atr14 rsi14 sma20 sma50 relvol a1 a2
[ "$C" = "$(printf '100\t0\t50\t100\t100\t1\t100\t100')" ]   || { echo "FAIL const: [$C]"; exit 1; }
[ "$R" = "$(printf '159\t2\t100\t149.5\t134.5\t1\t152\t124')" ] || { echo "FAIL ramp: [$R]"; exit 1; }
echo "PASS test-indicators"
