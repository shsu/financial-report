---
name: swing-alerts
description: Evaluate alert triggers on open swing positions - stop breached, A1 floor touched, target reached, move > 1 ATR, gap > 3%, fresh news. Prints only what fired; built for /loop 1h during market hours. Use when the user runs swing-alerts directly or via /loop.
---

# Swing Alerts

Designed to run repeatedly (`/loop 1h /swing-alerts` at the desk, market hours).
Cheap and quiet: when nothing fired, output exactly one line: `no alerts`.

## Procedure

1. `scripts/positions.sh` -> open positions. None -> print `no alerts` and stop.
2. `scripts/indicators.sh "<open tickers>"` (TSX/Taiwan get .TO/.TW suffix) for
   last, atr14, a1; Alpaca snapshot for today's open and prev close
   (`/v2/stocks/snapshots?symbols=...`, keys from ~/.claude.json, no feed=sip).
3. Fresh news on held names: `https://data.alpaca.markets/v1beta1/news?symbols=<held>&start=<last-run ISO>`
   with the same auth headers. Track last-run timestamp in
   `/tmp/swing-alerts-state.json` ({"last_run": "<ISO>"}); missing file = look
   back 24h. Update it at the end of every run (ephemeral is acceptable).
4. Evaluate per position, in this order:
   - last <= stop            -> "STOP: {ticker} {last} at/under stop {stop}"
   - last <= a1              -> "FLOOR: {ticker} {last} touched 7-day floor {a1}"
   - last >= target          -> "TARGET: {ticker} {last} reached target {target}"
   - (prev_close - last) > atr14 -> "ATR MOVE: {ticker} down {x.x} ATRs today"
   - |open - prev_close| / prev_close > 0.03 -> "GAP: {ticker} gapped {pct}% at open"
   - news item since last run -> "NEWS: {ticker} - {headline}"
5. Output ONLY fired alerts, one plain-English line each with the level/number
   that fired. Then deliver:
   - Terminal: always (the lines above).
   - PushNotification tool: if available, send one notification summarizing the
     fired alerts (skip when none fired).
   - Email: NOT YET CONFIGURED. When email credentials are provided, send fired
     alerts to stevenhsu0@gmail.com here. Until then, do nothing for email.
6. Skip rules: missing price/indicator data for a ticker -> print
   "DATA: {ticker} unavailable - skipped" (a skipped check never fires a false
   alert). Market closed (weekend/holiday/outside 06:30-13:00 PT) -> print
   `market closed` and stop before fetching.
