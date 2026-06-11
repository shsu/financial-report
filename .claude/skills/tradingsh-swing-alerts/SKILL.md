---
name: tradingsh-swing-alerts
description: Evaluate alert triggers on open swing positions - stop breached, prior 7-day floor touched, target reached, drop > 1 ATR, gap > 3%, fresh news. Prints only what fired; built for /loop 1h during market hours. Use when the user runs tradingsh-swing-alerts directly or via /loop.
---

# Swing Alerts

Designed to run repeatedly (`/loop 1h /tradingsh-swing-alerts` at the desk, market hours).
Cheap and quiet: when nothing fired, output exactly one line: `no alerts`.

## Procedure

1. `scripts/positions.sh` -> open positions. None -> print `no alerts` and stop.
2. `scripts/indicators.sh "<open tickers>"` for last and atr14 (suffix rule by
   account currency: CAD -> .TO, TWD -> .TW; USD unchanged). Today's open,
   prev close, and today's low: US tickers via ONE Alpaca snapshot call
   (`/v2/stocks/snapshots?symbols=...`, keys from ~/.claude.json, no feed=sip) -
   do NOT include .TO/.TW names in that call (a single foreign symbol 400s the
   whole request); for .TO/.TW names read the last two daily bars from the Yahoo
   chart API (`range=5d&interval=1d`).
3. Fresh news on held names: `https://data.alpaca.markets/v1beta1/news?symbols=<held>&start=<last-run ISO>`
   with the same auth headers - US-listed tickers only (the news API is
   US-centric; skip TSX/TWSE-only names like XCHP or 0050). Track last-run
   timestamp in /tmp/swing-alerts-state.json ({"last_run": "<ISO>"}); missing
   file = look back 24h. Update it at the end of every run (ephemeral is fine).
4. Evaluate per position, in this order:
   - last <= stop            -> "STOP: {ticker} {last} at/under stop {stop}"
   - today's low <= prior 7-day floor -> "FLOOR: {ticker} {low} touched prior
     7-day floor {floor}". Prior floor = min of the PREVIOUS 7 sessions' lows,
     EXCLUDING today - indicators.sh a1 includes today's partial bar, so do not
     use it raw; compute from daily bars (Alpaca /v2/stocks/bars timeframe=1Day
     for US; the same Yahoo chart response for .TO/.TW).
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
6. Skip rules: missing data for a specific check -> skip THAT CHECK only and
   print "DATA: {ticker} {check} unavailable - skipped" (a skipped check never
   fires a false alert; a position without stop/target simply has no STOP/TARGET
   check - that is not a data failure). Market closed (weekend/holiday/outside
   06:30-13:00 PT) -> print `market closed` and stop before fetching.
