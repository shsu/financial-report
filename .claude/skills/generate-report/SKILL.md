---
name: generate-report
description: Generate the Tier-1 market report on demand (same methodology as the 6am cloud routine) and then Display it, Email it, or save it as Markdown into docs/reports/. Use when the user asks to "generate report", "run the report", "market report now", or "tier 1 report".
---

# Generate Report

Produce the Daily Tier-1 report interactively, then deliver it the way the user picks.

## Steps

1. **Load inputs.**
   - Tier membership: read `data/tiers.json` (source of truth — do NOT use the ticker
     lists hard-coded anywhere else if they disagree; flag the mismatch instead).
   - Methodology: read `prompts/daily-tier1-report.md` and follow its STEP 0–5 exactly,
     including the plain-English style rule.
   - Alpaca keys: `jq -r '.mcpServers.alpaca.env' ~/.claude.json` — substitute into the
     `${ALPACA_API_KEY}` placeholders. Data endpoints only (`data.alpaca.markets`);
     never the trading API. Do not pass `feed=sip` (403 on this plan).
   - `scripts/fetch-bars-stats.sh` does the paginated bars fetch if you want a shortcut.

2. **Generate the report** as a single markdown document. If the user asked for a quick
   version, STEP 1B fundamentals and STEP 2 option walls may be skipped — say so in the
   report footer.

3. **Ask how to deliver it** with AskUserQuestion (multiSelect: true), options:
   - **Display** — print the full report in the conversation.
   - **Email** — send via the Gmail MCP connector (authenticate first if needed) to
     stevenhsu0@gmail.com, subject `Daily Tier-1 Report — {YYYY-MM-DD}`, report as the
     body (markdown). If Gmail MCP is unavailable, say so and offer the other two.
   - **Save Markdown** — write to `docs/reports/{YYYY-MM-DD}-tier1-report.md` in this
     repo. Do not commit/push unless the user asks.

4. Honor every selected option (multiple allowed).

## Notes

- Always recompute levels fresh; never reuse numbers from a previous report.
- End the report with the one-line data-source success/failure list. If sources fail,
  run `scripts/check-data-sources.sh` and include the relevant finding.
