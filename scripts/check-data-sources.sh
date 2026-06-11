#!/usr/bin/env bash
# Health check for every endpoint the report routines depend on.
# Expected-good output (as of 2026-06-11):
#   sip=403 (known: free plan), everything else 200, crumb non-empty,
#   FRED may 504 (known outage — routines treat it as fallback only).
set -uo pipefail

if [ -z "${ALPACA_API_KEY:-}" ]; then
  ALPACA_API_KEY=$(jq -r '.mcpServers.alpaca.env.ALPACA_API_KEY' ~/.claude.json)
  ALPACA_SECRET_KEY=$(jq -r '.mcpServers.alpaca.env.ALPACA_SECRET_KEY' ~/.claude.json)
fi
A=(-H "APCA-API-KEY-ID: $ALPACA_API_KEY" -H "APCA-API-SECRET-KEY: $ALPACA_SECRET_KEY")
UA=(-H "User-Agent: Mozilla/5.0")
code() { curl -s -o /dev/null -w "%{http_code}" --max-time 15 "$@"; }

echo "alpaca snapshot (default feed): $(code "https://data.alpaca.markets/v2/stocks/snapshots?symbols=NVDA" "${A[@]}")   <- want 200"
echo "alpaca snapshot (feed=sip):     $(code "https://data.alpaca.markets/v2/stocks/snapshots?symbols=NVDA&feed=sip" "${A[@]}")   <- 403 expected on free plan"
echo "alpaca weekly bars:             $(code "https://data.alpaca.markets/v2/stocks/bars?symbols=NVDA,MU&timeframe=1Week&adjustment=split&start=2025-06-05&limit=10000" "${A[@]}")   <- want 200"
echo "alpaca options chain:           $(code "https://data.alpaca.markets/v1beta1/options/snapshots/MU?feed=indicative&limit=10" "${A[@]}")   <- want 200"
echo "alpaca crypto BTC/USD:          $(code "https://data.alpaca.markets/v1beta3/crypto/us/snapshots?symbols=BTC/USD" "${A[@]}")   <- want 200"
echo "yahoo chart ^VIX:               $(code "https://query1.finance.yahoo.com/v8/finance/chart/%5EVIX?range=5d&interval=1d" "${UA[@]}")   <- want 200"
echo "yahoo chart XCHP.TO:            $(code "https://query1.finance.yahoo.com/v8/finance/chart/XCHP.TO?range=1y&interval=1wk" "${UA[@]}")   <- want 200"
echo "yahoo chart 2YY=F (2yr yield):  $(code "https://query1.finance.yahoo.com/v8/finance/chart/2YY%3DF?range=5d&interval=1d" "${UA[@]}")   <- want 200"

curl -s -c /tmp/yc_check.txt "${UA[@]}" --max-time 15 "https://fc.yahoo.com" -o /dev/null
CRUMB=$(curl -s -b /tmp/yc_check.txt "${UA[@]}" --max-time 15 "https://query1.finance.yahoo.com/v1/test/getcrumb")
echo "yahoo crumb:                    [${CRUMB:0:12}]   <- want non-empty"
echo "yahoo quoteSummary NVDA:        $(code -b /tmp/yc_check.txt "https://query1.finance.yahoo.com/v10/finance/quoteSummary/NVDA?modules=defaultKeyStatistics&crumb=$CRUMB" "${UA[@]}")   <- want 200"
echo "FRED DGS2 csv:                  $(code "https://fred.stlouisfed.org/graph/fredgraph.csv?id=DGS2")   <- 504 = known outage; routines fall back to 2YY=F"
