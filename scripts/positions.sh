#!/usr/bin/env bash
# Derive positions from the trade journal. Average-cost method (matches Canadian
# ACB convention). Columns: ticker account currency qty avg_cost realized_pnl
# stop target state. Positions are ALWAYS derived - never stored.
# Usage: positions.sh [trades.json]   (default: data/trades.json)
set -euo pipefail
TRADES="${1:-data/trades.json}"

jq -r '
  def round2: . * 100 | round / 100;
  (.trades // error("no .trades array in journal"))
  | sort_by(.date, .id)
  | group_by([.ticker, .account])
  | map(
      reduce .[] as $t (
        { ticker: .[0].ticker, account: .[0].account, currency: .[0].currency,
          qty: 0, avg: 0, realized: 0, stop: null, target: null };
        if $t.qty <= 0 then error("non-positive qty in \($t.id // "<no id>")")
        elif $t.side == "buy" then
          .avg = ((.avg * .qty + $t.price * $t.qty) / (.qty + $t.qty))
          | .qty += $t.qty
        elif $t.side == "sell" then
          (if $t.qty > .qty then error("oversell of \(.ticker)/\(.account) at \($t.id // "<no id>")") else . end)
          | .realized += ($t.qty * ($t.price - .avg))
          | .qty -= $t.qty
        else error("unknown side: \($t.side)") end
        | .stop   = ($t.stop   // .stop)
        | .target = ($t.target // .target)
      )
    )
  | .[]
  | [ .ticker, .account, .currency, .qty, (.avg|round2), (.realized|round2),
      (.stop // "-"), (.target // "-"),
      (if .qty > 0 then "open" else "closed" end) ]
  | @tsv
' "$TRADES"
