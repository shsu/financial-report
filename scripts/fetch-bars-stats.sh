#!/usr/bin/env bash
# Fetch split-adjusted weekly bars from Alpaca for a symbol list (handles the
# pagination trap: multi-symbol responses paginate even under the limit) and print
# per-symbol trend stats: last close, 1-yr %, 3-mo %, max high, % off high.
#
# Usage: ./fetch-bars-stats.sh "QQQM,AVLV,AVIV,DRAM,POW,AIS" [start-date]
# Keys:  read from ~/.claude.json (mcpServers.alpaca.env) unless ALPACA_API_KEY is set.
set -euo pipefail

SYMS="${1:?usage: fetch-bars-stats.sh SYM1,SYM2,... [start-date]}"
START="${2:-$(date -v-2y +%Y-%m-%d 2>/dev/null || date -d '2 years ago' +%Y-%m-%d)}"
YOY_DATE=$(date -v-1y +%Y-%m-%d 2>/dev/null || date -d '1 year ago' +%Y-%m-%d)
M3_DATE=$(date -v-3m +%Y-%m-%d 2>/dev/null || date -d '3 months ago' +%Y-%m-%d)

if [ -z "${ALPACA_API_KEY:-}" ]; then
  ALPACA_API_KEY=$(jq -r '.mcpServers.alpaca.env.ALPACA_API_KEY' ~/.claude.json)
  ALPACA_SECRET_KEY=$(jq -r '.mcpServers.alpaca.env.ALPACA_SECRET_KEY' ~/.claude.json)
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TOKEN=""
for _ in $(seq 1 20); do
  URL="https://data.alpaca.markets/v2/stocks/bars?symbols=$SYMS&timeframe=1Week&adjustment=split&start=$START&limit=10000"
  [ -n "$TOKEN" ] && URL="$URL&page_token=$TOKEN"
  curl -s --max-time 30 "$URL" \
    -H "APCA-API-KEY-ID: $ALPACA_API_KEY" \
    -H "APCA-API-SECRET-KEY: $ALPACA_SECRET_KEY" > "$TMP/page.json"
  jq -c '.bars' "$TMP/page.json" >> "$TMP/pages.jsonl"
  TOKEN=$(jq -r '.next_page_token // empty' "$TMP/page.json")
  [ -z "$TOKEN" ] && break
done

jq -s 'reduce .[] as $p ({}; reduce ($p|to_entries[]) as $e (.; .[$e.key] = ((.[$e.key] // []) + $e.value)))' \
  "$TMP/pages.jsonl" > "$TMP/bars.json"

echo -e "symbol\tbars\tfirst\tlast_close\tyoy%\t3mo%\tmax_high\toff_high%"
jq -r --arg yoy "$YOY_DATE" --arg m3 "$M3_DATE" '
  to_entries[] | .key as $s | (.value | sort_by(.t)) as $b |
  ($b[-1].c) as $last |
  (($b | map(select(.t >= $yoy)) | .[0].c) // null) as $y |
  (($b | map(select(.t >= $m3))  | .[0].c) // null) as $q |
  ($b | map(.h) | max) as $maxh |
  [$s, ($b|length), $b[0].t[0:10], $last,
   (if $y then (100*($last/$y - 1)|round) else "n/a" end),
   (if $q then (100*($last/$q - 1)|round) else "n/a" end),
   $maxh, (100*($last/$maxh - 1)|round)] | @tsv' "$TMP/bars.json" | sort

echo "---"
echo "symbols returned: $(jq -r 'keys|join(",")' "$TMP/bars.json")"
echo "(compare against requested list — missing symbols mean a pagination/coverage gap)"
