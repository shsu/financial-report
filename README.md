# financial-report

Personal market-research playbook and automation, built with Claude Code (June 2026).
Covers the tier-based watchlist system (stocks + ETFs), the data plumbing that feeds it,
and the prompts for the two scheduled cloud agents that produce daily reports.

## Layout

| Path | What it is |
|---|---|
| `docs/tier-framework.md` | The rules: stock tiers, ETF tiers, entry discipline, macro gate, action semantics |
| `docs/data-sources.md` | Alpaca/Yahoo/FRED plumbing, auth, and every gotcha hit so far |
| `docs/current-book-2026-06.md` | Snapshot of the actual book as of June 2026 (stock ranks, ETF tier table, fee map, macro context) |
| `prompts/daily-tier1-report.md` | Cloud routine prompt: 6am weekday Tier-1 report (levels, actions, ETF snapshot, fundamentals) |
| `prompts/midday-market-summary.md` | Cloud routine prompt: noon weekday descriptive summary (no recommendations) |
| `prompts/regenerate-tier1-etfs.md` | Paste-in prompt to rebuild the Tier-1 ETF table in an interactive session |
| `scripts/fetch-bars-stats.sh` | Paginated Alpaca weekly-bars fetch + per-symbol trend stats |
| `scripts/check-data-sources.sh` | Health check for every endpoint the routines depend on |
| `data/tiers.json` | **Source of truth** for tier membership — STOCKS: tier1 (ranked, junior/probation flags) / tier2 / cut · ETFs: tier1 (ranked, category/fee/action) / tier2 / cut |
| `.claude/skills/tradingsh-generate-report/` | Skill: build the Tier-1 report on demand → Display / Email / save to `docs/reports/` |
| `.claude/skills/tradingsh-tier-admission/` | Skill: gate NEW stocks into Tier 1/2 via `equity-research:screen`; updates `data/tiers.json` |
| `data/trades.json` | Append-only swing-trade journal — positions always derived, never stored |
| `scripts/positions.sh` | trades.json → positions (avg-cost, realized P&L, latest stop/target) |
| `scripts/lib/indicators.jq` + `scripts/indicators.sh` | ATR14/RSI14/SMA/relvol/A1/A2 from Alpaca + Yahoo bars |
| `tests/` | `run-tests.sh` (offline fixture tests) + live smoke test |
| `.claude/skills/tradingsh-log-trade/` | Skill: record trades (single / bulk import / seed current holdings) |
| `.claude/skills/tradingsh-swing-status/` | Skill: on-demand position dashboard (P&L, stops, ATR/RSI, concentration) |
| `.claude/skills/tradingsh-swing-alerts/` | Skill: trigger scan for `/loop 1h` — prints only what fired |

## Skills (work when Claude Code runs inside this repo)

- **tradingsh-generate-report** — "generate report" / "market report now". Reads `data/tiers.json`
  + the routine prompt for methodology, then asks Display | Email (Gmail MCP →
  stevenhsu0@gmail.com) | Save Markdown (`docs/reports/YYYY-MM-DD-tier1-report.md`).
- **tradingsh-tier-admission** — "evaluate XYZ for tier". Stocks only, admission only: runs the
  `equity-research:screen` methodology against the admission bar in
  `docs/tier-framework.md`, writes admits into `data/tiers.json`, and reminds that the
  cloud routine prompts embed ticker lists and need a `/schedule` update to match.
- **tradingsh-log-trade / tradingsh-swing-status / tradingsh-swing-alerts** — local-first swing-trading suite
  (see `docs/superpowers/specs/2026-06-11-swing-trading-local-design.md`).
  Typical day: `/loop 1h` invoking tradingsh-swing-alerts while at the desk; `tradingsh-swing-status`
  on demand; every fill logged via tradingsh-log-trade (which auto-commits + pushes).
  Cloud routines deliberately do NOT read positions (Approach C). Email delivery
  TBD pending credentials; PushNotification is the interim alert channel.

`data/tiers.json` outranks any ticker list hard-coded in docs or prompts — if they
disagree, the JSON is current and the prompt needs updating.

## Security

**No API keys are committed to this repo.** Prompts and scripts reference
`${ALPACA_API_KEY}` / `${ALPACA_SECRET_KEY}`. Locally they live in
`~/.claude.json` under `mcpServers.alpaca.env`. The *live* cloud routine prompts embed
the literal keys (cloud sessions have no access to local env) — those keys are
data-plan-only (free tier, no trading entitlement) and every prompt carries a guardrail
restricting calls to `data.alpaca.markets`. If a key leaks, rotate it in the Alpaca
dashboard and update both routines.

## Live cloud routines

Managed at <https://claude.ai/code/routines> (update via Claude Code `/schedule`; deletion is web-only).

| Routine | ID | Schedule (UTC) | Local |
|---|---|---|---|
| Daily Tier-1 Market Report | `trig_01JgehigiHA3muyMddJwTXLa` | `0 13 * * 1-5` | 6:00 AM PDT weekdays |
| Midday Market Summary | `trig_01MpR9wRC5xtKQachnyQbbs9` | `0 19 * * 1-5` | 12:00 PM PDT weekdays |

Cron is fixed UTC: when clocks fall back (PST), these fire at 5am/11am local unless re-set.

Both run `claude-fable-5`, no repo checkout, no MCP requirements (pure curl + web search).
Both reports end with a one-line list of which data sources succeeded/failed — read that
line first when a report looks off, then run `scripts/check-data-sources.sh` to localize
the breakage.
