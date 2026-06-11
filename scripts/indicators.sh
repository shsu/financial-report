#!/usr/bin/env bash
# Indicators for a symbol list. US symbols via Alpaca daily bars (split-adjusted,
# paginated, NO feed=sip - 403 on this plan). Symbols ending .TO or .TW via Yahoo
# chart API. Output TSV: symbol last atr14 rsi14 sma20 sma50 relvol a1 a2
# Usage: indicators.sh "NVDA,MU,XCHP.TO"
set -euo pipefail
SYMS="${1:?usage: indicators.sh SYM1,SYM2,...   (.TO/.TW suffix for TSX/Taiwan)}"
cd "$(dirname "$0")/.."

if [ -z "${ALPACA_API_KEY:-}" ]; then
  ALPACA_API_KEY=$(jq -r '.mcpServers.alpaca.env.ALPACA_API_KEY' ~/.claude.json)
  ALPACA_SECRET_KEY=$(jq -r '.mcpServers.alpaca.env.ALPACA_SECRET_KEY' ~/.claude.json)
fi
START=$(date -v-150d +%Y-%m-%d 2>/dev/null || date -d '150 days ago' +%Y-%m-%d)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

US=$(echo "$SYMS" | tr ',' '\n' | grep -v '\.' | paste -sd, - || true)
FOREIGN=$(echo "$SYMS" | tr ',' '\n' | grep '\.' || true)

echo '{}' > "$TMP/bars.json"
if [ -n "$US" ]; then
  TOKEN=""
  for _ in $(seq 1 20); do
    URL="https://data.alpaca.markets/v2/stocks/bars?symbols=$US&timeframe=1Day&adjustment=split&start=$START&limit=10000"
    [ -n "$TOKEN" ] && URL="$URL&page_token=$TOKEN"
    curl -s --max-time 30 "$URL" \
      -H "APCA-API-KEY-ID: $ALPACA_API_KEY" -H "APCA-API-SECRET-KEY: $ALPACA_SECRET_KEY" > "$TMP/page.json"
    jq -s '.[0] as $acc | .[1].bars | to_entries
           | reduce .[] as $e ($acc; .[$e.key] = ((.[$e.key] // []) + $e.value))' \
      "$TMP/bars.json" "$TMP/page.json" > "$TMP/bars2.json" && mv "$TMP/bars2.json" "$TMP/bars.json"
    TOKEN=$(jq -r '.next_page_token // empty' "$TMP/page.json")
    [ -z "$TOKEN" ] && break
  done
fi
for F in $FOREIGN; do
  curl -s --max-time 15 -H "User-Agent: Mozilla/5.0" \
    "https://query1.finance.yahoo.com/v8/finance/chart/$F?range=1y&interval=1d" > "$TMP/y.json"
  jq -s --arg s "$F" '.[0] as $acc | .[1].chart.result[0] as $r
    | $acc + { ($s): ([range(0; $r.timestamp|length)
        | { t: $r.timestamp[.], o: $r.indicators.quote[0].open[.],
            h: $r.indicators.quote[0].high[.], l: $r.indicators.quote[0].low[.],
            c: $r.indicators.quote[0].close[.], v: $r.indicators.quote[0].volume[.] }]
        | map(select(.c != null))) }' "$TMP/bars.json" "$TMP/y.json" > "$TMP/bars2.json" \
    && mv "$TMP/bars2.json" "$TMP/bars.json"
done

echo -e "symbol\tlast\tatr14\trsi14\tsma20\tsma50\trelvol\ta1\ta2"
jq -r -L scripts/lib 'include "indicators";
  to_entries[] | [.key] + (.value | sort_by(.t) | indicators) | @tsv' "$TMP/bars.json"

GOT=$(jq -r 'keys | join(",")' "$TMP/bars.json")
for S in $(echo "$SYMS" | tr ',' ' '); do
  echo "$GOT" | tr ',' '\n' | grep -qx "$S" || { echo "ERROR: no data for $S" >&2; exit 1; }
done
