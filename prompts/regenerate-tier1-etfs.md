# Interactive prompt: regenerate the Tier-1 ETF table

Paste into `/equity-research:screen` in a Claude Code session (the session has local
access to `~/.claude.json` for Alpaca creds, unlike the cloud routines).

```text
Regenerate Tier 1 ETF table. Prices: Alpaca for US tickers (curl, creds in ~/.claude.json, split-adjusted weekly bars, paginate next_page_token); TSX/TWSE via web — Alpaca "QQC" is a DIFFERENT US fund, always quote TSX QQC. Columns: #, ticker, category, fee, price, 1Y%, 3-mo%, off-high%, action BUY|HOLD|DCA. Criteria: good fee; bonus for proven active mgmt; no penalty for SpaceX/private sleeves; max 1-2 funds per overlap cluster; user overrides = AIS stays #9, XCHP stays #10 as CAD FX-avoidance vehicle. Current T1: 1 0050 (Taiwan/TSM core), 2 QQQM (US growth beta), 3 AVLV (US value), 4 GARP (US quality-growth), 5 SCHD (income ballast), 6 AVIV (intl value), 7 DRAM jr (Korea memory/HBM), 8 POW jr (electrification/Asian grid), 9 AIS jr (AI umbrella + private sleeve), 10 XCHP (CAD semis beta, CAD cash only). Juniors = junior size, tiered-support adds only, respect air gaps. Re-derive BUY|HOLD|DCA from fresh momentum/off-high/macro; flag T2 names earning promotion (FLTW for USD-only accounts, AVXC, QQC) and any T1 breakdown.
```
