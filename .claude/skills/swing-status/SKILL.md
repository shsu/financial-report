---
name: swing-status
description: On-demand swing-position dashboard - unrealized P&L, distance to stop/target, ATR and RSI context, price vs A1/A2 floors, concentration check. Use when the user asks "status", "where am I", "how are my positions", or "swing status".
---

# Swing Status

Read-only. Data flow: `scripts/positions.sh` (open positions) ->
`scripts/indicators.sh "<open tickers>"` (TSX/Taiwan names get .TO/.TW suffixes;
0050 -> 0050.TW) -> join -> report.

## Report (plain English per the house style rule - no jargon)

1. **Per open position** (one row each): qty @ avg cost -> last price,
   unrealized P&L in $ and % (position currency), days held (today - earliest
   open buy date), distance to stop and target ("stop 820 is 4.2% below"),
   ATR context ("down 1.3 ATRs from entry" = (avg - last)/atr14 when negative),
   RSI14, last vs A1/A2 ("sitting 2% above the 7-day floor").
2. **Rollups:** total unrealized P&L per currency and per account. NO FX
   conversion - report each currency natively.
3. **Concentration:** each position's share of its currency bucket; flag any
   name > 25% of its bucket; note AI-theme stacking (singles + DRAM/POW/AIS/
   XCHP/QQQM overlap) in one sentence.
4. **Flags:** last <= stop ("STOP BREACHED"); last >= target; earnings within
   5 sessions (check via Yahoo calendarEvents crumb flow from
   docs/data-sources.md, or web search); held > 30 days with negative P&L
   ("stale swing - revisit thesis").

No trade recommendations beyond the flags - this is a dashboard, not the
daily report. If data/trades.json has no open positions, say so and stop.
