---
name: log-trade
description: Record swing trades into data/trades.json - single trades in plain English ("bought 10 MU at 858.50 in IBKR, stop 820"), bulk import of pasted fills/CSV/broker confirmations, or seeding current holdings. Validates, previews, appends, auto-commits and pushes. Use when the user says "log trade", "bought/sold X", "import trades", or "seed my positions".
---

# Log Trade

Sole writer of `data/trades.json`. Every path ends: validate -> preview -> append ->
auto-commit + push. Positions are derived, never edited directly.

## Input modes

1. **Single trade, plain English.** Parse ticker, side, qty, price; optional stop,
   target, thesis, account, date (default today), setup. "sold half my DRAM" /
   "sold all" resolve against the current position from `scripts/positions.sh`.
   Defaults: account inferred from currency when unambiguous (USD -> ibkr-usd,
   CAD -> tfsa-cad, TWD -> tw-broker - confirm first use and reuse); setup
   suggested from context but always shown for correction.
2. **Bulk import.** User pastes anything (lines, CSV, broker confirmation text).
   Parse every fill found; show ONE preview table (date, ticker, side, qty, price,
   currency, account, setup); single confirmation; append all. List unparseable
   lines verbatim - never guess them.
3. **Seed mode.** "seed my positions: 10 MU @ 858, 100 XCHP @ 131 CAD tfsa" ->
   one trade per holding with setup "seed", price = average cost, date = today
   unless given. This bootstraps the book without history.

## Procedure

1. Parse input into candidate trade objects (schema in data/trades.json header).
2. Validate each: qty > 0; price > 0; side in buy|sell; selling more than the
   currently held qty cannot be appended (the journal validator hard-errors on
   oversells) - if the user insists the sale is real, the journal is missing
   history: seed the missing shares first (seed mode), then log the sale;
   ticker missing from
   every tier in data/tiers.json -> warn but allow.
3. Show the preview table and get one confirmation (AskUserQuestion or plain
   chat confirm; skip the question only if the user already gave an unambiguous
   complete instruction in this turn).
4. Assign ids: `YYYY-MM-DD-NNN`, NNN = next free integer for that date.
5. Append atomically: build the new file with jq into a temp file, `jq -e .`
   validate, `scripts/positions.sh /tmp/newfile` must exit 0 (catches negative
   positions and oversells), then move into place.
6. Echo the updated derived position lines for the affected tickers.
7. `git add data/trades.json && git commit` (message: "journal: <summary>",
   end with the Claude co-author line) `&& git push`. Push failure = warn only.
