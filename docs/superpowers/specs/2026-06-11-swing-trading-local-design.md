# Swing-trading local skills — design

**Date:** 2026-06-11 · **Approach:** C ("local-first, cloud-light") — approved by Steven.

## Goal

Day-to-day position awareness for swing trading, delivered entirely through local
Claude Code skills in this repo. The two cloud routines (Daily Tier-1 Report, Midday
Market Summary) stay exactly as they are: watchlist-only, no repo source, no position
data. No new cloud routines.

## Non-goals (explicitly out of scope)

- Cloud routines reading positions or tiers from the repo (that was Approach A — rejected).
- Options trades, dividend tracking, FX P&L conversion between accounts.
- Broker API integration or automated CSV sync.
- Tier-1-vs-benchmark backtesting, catalyst calendar data file.
- Email delivery (TBD — user is obtaining keys; design leaves a pluggable seam).

## Components

### 1. `data/trades.json` — append-only trade journal (single source of truth)

```json
{ "trades": [ {
    "id": "2026-06-11-001",
    "date": "2026-06-11",
    "ticker": "MU",
    "side": "buy",
    "qty": 10,
    "price": 858.50,
    "currency": "USD",
    "account": "ibkr-usd",
    "setup": "A1-buy",
    "thesis": "HBM LTA thesis, entry zone 854-864",
    "stop": 820.0,
    "target": 1000.0
} ] }
```

- `setup` enum: `A1-buy | DCA | junior-tranche | breakout | trim | exit-stop |
  exit-target | seed | other`. `seed` marks synthetic entries used to backfill
  existing holdings (approximate date allowed, price = average cost).
- `stop`/`target`/`thesis` optional. `id` = `date-NNN` (NNN increments within a day).
- **Positions are always derived, never stored** — no second source of truth.
- Committed to the private GitHub repo (decision: backup + multi-machine beats
  keeping it laptop-only; repo privacy already verified).
- Only the `log-trade` skill writes this file. Everything else is a reader.

### 2. Skill: `log-trade` (.claude/skills/log-trade/SKILL.md)

Three input modes, all ending in: validate → preview → append → auto-commit + push.

1. **Single trade, plain English.** "bought 10 MU at 858.50 in IBKR, stop 820" /
   "sold half my DRAM at 62". Resolves "half"/"all" against the current derived
   position. Defaults: date = today, account inferred from currency if unambiguous,
   setup inferred from context (price ≤ known A1 → suggest `A1-buy`) but always shown
   in the preview for correction.
2. **Bulk import.** User pastes anything — multiple lines, CSV, a broker
   confirmation blob. Skill parses every fill it can find, shows ONE preview table
   (date, ticker, side, qty, price, currency, account, setup), asks for a single
   confirmation, then appends all. Unparseable lines are listed, never guessed.
3. **Seed mode.** "import my current positions: 10 MU @ 858, 200 XCHP @ 131 CAD tfsa…"
   → one `seed` trade per holding dated today (or user-supplied date), price =
   average cost. Gets the book accurate on day one without full history.

Validation: qty > 0; selling more than held requires explicit confirmation; ticker
not in any tier of `data/tiers.json` → warn but allow; `jq -e` on the file before
commit. Echo the updated derived position after every append.

### 3. Skill: `swing-status` (.claude/skills/swing-status/SKILL.md)

On-demand. Derive positions (`scripts/positions.sh`), fetch live prices (Alpaca for
US; Yahoo `.TO`/`.TW` for TSX/Taiwan), compute indicators (`scripts/indicators.sh`),
then report in plain English (house style rule):

- Per position: qty, average cost, unrealized P&L ($ and %), days held, distance to
  stop and target, ATR(14) context ("down 1.3 ATRs from entry"), RSI(14), price vs
  A1 (7-session low) / A2 (35-session low).
- Rollups by account and currency (no FX conversion — report each currency natively).
- Concentration check: per-name % of book and AI-theme stacking across singles + ETFs.
- Flags: stop breached, target reached, earnings within 5 sessions (Yahoo
  calendarEvents or web search), position older than 30 days with negative P&L
  ("stale swing").

### 4. Skill: `swing-alerts` (.claude/skills/swing-alerts/SKILL.md)

Built to be invoked repeatedly via `/loop 1h /swing-alerts` during market hours at
the desk. Each run: derive positions → fetch prices/indicators + Alpaca News API
(`/v1beta1/news?symbols=<held tickers>`) → evaluate triggers:

- price ≤ stop (planned stop from the trade log)
- price ≤ A1 for a held name, or ≥ target
- adverse move > 1×ATR(14) vs prior close
- gap > 3% at the open
- fresh news headline on a held name (since last run; track last-seen timestamp in
  `/tmp/swing-alerts-state.json` — ephemeral is acceptable)

Output: ONLY fired alerts, one plain-English line each with the level that fired.
Nothing fired → single line "no alerts". Quiet by design — a loop run should cost
seconds when nothing happened.

**Delivery seam:** terminal always; PushNotification tool additionally for fired
alerts (works today, no keys). Email: stubbed section in the skill ("when email
credentials are configured, send fired alerts to stevenhsu0@gmail.com") — wired up
later when the user's keys arrive. Note: the Gmail MCP connector currently exposes
draft-creation only, not send; expect SMTP app-password or API key instead.

### 5. Scripts (shared math, used by all three skills)

- `scripts/positions.sh` — reads `data/trades.json`, emits per-ticker/account:
  net qty, average cost (average-cost method — matches Canadian ACB convention),
  realized P&L per closed lot, open-position list. jq implementation; TSV out.
- `scripts/indicators.sh` — input: symbol list. Fetch 60+ sessions of split-adjusted
  daily bars from Alpaca (paginated, no `feed=sip`), Yahoo chart for `.TO`/`.TW`.
  Output per symbol: last close, ATR14, RSI14, SMA20, SMA50, relative volume
  (today ÷ 20-day average), 7-session low (A1), 35-session low (A2). TSV out.
- Both follow existing script conventions: keys from `~/.claude.json` unless env
  set, `--max-time`, loud failure when a requested symbol is missing from output.

### 6. Data sources (additions decided during brainstorm)

- **Alpaca News API** (`data.alpaca.markets/v1beta1/news`) — free on existing key;
  used by `swing-alerts` (and available to others). Add to `docs/data-sources.md`.
- **No TradingView MCP.** Indicators are computed in `scripts/indicators.sh` from
  Alpaca bars. Document the unofficial `scanner.tradingview.com` curl in
  `docs/data-sources.md` as an optional cross-check, clearly marked unofficial/fragile.

## Error handling

- `log-trade` is the sole writer; skills never mutate during reads.
- Append is atomic: write temp file, `jq -e` validate, then move into place; commit
  only after validation passes. Push failure = warn, don't block (commit is the record).
- Price fetch failures degrade per-symbol: report "price unavailable" for that name,
  never fabricate; alerts skip (not fire) on missing data and say so.
- `positions.sh` exits non-zero on malformed trades (negative resulting position
  without a prior confirmation marker).

## Testing

- Fixture-driven: `tests/fixtures/trades-sample.json` covering buy → DCA → partial
  sell → full exit, multi-account, multi-currency, a seed entry; assert
  `positions.sh` output (qty, avg cost, realized P&L) against known-good values.
- `indicators.sh` smoke test against 2 live symbols (one US, one `.TO`) — assert all
  columns populated.
- Skill walkthrough: seed 2 positions, log 1 trade, run swing-status and
  swing-alerts once; verify outputs by hand before calling it done.

## Open items

- Email delivery: blocked on user obtaining keys. Re-open the `swing-alerts`
  delivery section then.
- Tiers-sync between `data/tiers.json` and cloud routine prompts remains manual
  (accepted trade-off of Approach C; `tier-admission` skill reminds on every admit).
