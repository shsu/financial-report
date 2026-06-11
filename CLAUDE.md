# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A personal market-research playbook and trading toolkit: bash+jq scripts, JSON data
files, markdown docs, and Claude Code skills (`.claude/skills/tradingsh-*`). There is
no build step, package manager, or app server. Platform is macOS (BSD userland: use
`date -v` with a GNU fallback, no `grep -P`).

## Commands

```bash
tests/run-tests.sh           # offline test suite (fixture-driven, no network)
tests/test-positions.sh      # single test: position derivation math
tests/test-indicators.sh     # single test: indicator math (generated fixtures)
tests/smoke-indicators.sh    # LIVE network smoke test (Alpaca + Yahoo) - run manually
scripts/check-data-sources.sh  # health-check every external endpoint with expected codes

scripts/positions.sh [trades.json]      # derive positions (default: data/trades.json)
scripts/indicators.sh "NVDA,XCHP.TO"    # ATR14/RSI14/SMA/relvol/A1/A2 per symbol
```

Run offline tests after touching anything in `scripts/` — the fixtures pin exact
window math (a 15-bar ATR bug or relvol off-by-one fails the suite).

## Architecture

**Two sources of truth, everything else derived or generated:**

- `data/trades.json` — append-only trade journal. Positions are ALWAYS derived by
  `scripts/positions.sh` (average-cost/ACB; oversells hard-error at the offending
  trade) and never stored anywhere. Only the `tradingsh-log-trade` skill writes this
  file; append atomically (temp file → `jq -e` → positions.sh must exit 0 → move).
- `data/tiers.json` — tier membership for stocks AND ETFs. It outranks any ticker
  list hard-coded in docs or prompts. The cloud routine prompts embed their own
  ticker universes, so a tiers.json change requires updating the routines via
  `/schedule` (the routine IDs and full prompt copies live in `prompts/*.md`).

**Math/IO split:** `scripts/lib/indicators.jq` is pure jq math (testable offline via
`jq -L scripts/lib`); `scripts/indicators.sh` is the fetch wrapper (Alpaca for US,
Yahoo chart API for `.TO`/`.TW` suffixes only — dotted US classes like BRK.B stay on
Alpaca). Note: A1/A2 (7-/35-session lows) include today's partial bar intraday.

**Skills orchestrate scripts.** The five `tradingsh-*` skills are markdown procedures:
log-trade (sole journal writer), swing-status (dashboard), swing-alerts (built for
`/loop 1h`), generate-report (Tier-1 report → Display/Email/save), tier-admission
(stocks only, admission only — invokes `equity-research:screen` as its evaluation
engine; ETF membership is governed by the fee/overlap criteria in
`docs/tier-framework.md`, never by this skill).

**Cloud routines are deliberately position-blind** (Approach C in
`docs/superpowers/specs/`): the two scheduled cloud agents read no repo data and never
see `trades.json`. Don't "fix" that by attaching the repo to them.

## Hard rules

- **No secrets in this repo, ever.** Alpaca keys are read at runtime from
  `~/.claude.json` (`mcpServers.alpaca.env`). The committed prompt copies use
  `${ALPACA_API_KEY}` placeholders.
- The Alpaca key is data-plan-only: `data.alpaca.markets` endpoints exclusively,
  never the trading API, and never `feed=sip` (HTTP 403 on this plan; omit the
  feed param or use `feed=iex`).
- Alpaca multi-symbol bar responses paginate even under the `limit` — always loop
  `next_page_token` and validate each page, or symbols silently drop. Failures must
  be loud (exit non-zero), never silent partial data.
- TSX/TWSE tickers never go to Alpaca bare: Alpaca returns a *different US fund* for
  collisions like `QQC`. Full gotcha list: `docs/data-sources.md`.
- Generated reports follow the plain-English style rule (reader is an engineer, not
  a finance person): no unexplained jargon, terms defined on first use.
- Commits are SSH-signed via the 1Password agent; if commits/pushes fail with
  "agent returned an error" or "agent refused operation", 1Password is locked —
  ask the user to unlock rather than disabling signing.

## Design history

`docs/superpowers/specs/` and `docs/superpowers/plans/` record why things are shaped
this way (notably the 2026-06-11 swing-trading spec). Check there before proposing
structural changes — several "obvious improvements" (storing positions, attaching the
repo to cloud routines, TradingView MCP) were considered and rejected with reasons.
