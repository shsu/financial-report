---
name: tradingsh-tier-admission
description: Evaluate candidate STOCKS for admission into Tier 1 or Tier 2 using the equity-research:screen skill, and update data/tiers.json. Admission-only - never re-ranks or removes existing members, and never admits ETFs. Use when the user asks to "evaluate X for tier", "admit X", "should X be tier 1/2", or "screen X for the watchlist".
---

# Tier Admission

Gate for NEW stocks entering Tier 1/2. Scope is deliberately narrow:

- **Stocks only.** ETF membership is recorded in the `etfs` section of
  `data/tiers.json` but is managed by the fee/overlap criteria in
  `docs/tier-framework.md`, not by this skill — refuse ETF candidates and point there.
- **Admission only.** Demotions, cuts, and re-ranking of existing members are driven by
  the daily routine's conditionals (STEP 4 of `prompts/daily-tier1-report.md`), not by
  this skill. If the user asks to demote/remove, do it as a plain edit, not a screen.

## Steps

1. **Invoke the `equity-research:screen` skill** (idea-generation methodology) for the
   candidate ticker(s). Pull fresh data: Alpaca snapshot + split-adjusted weekly bars
   (keys from `~/.claude.json`, no `feed=sip`, paginate bars), fundamentals (forward
   P/E, PEG, gross margin, growth, next earnings) via Yahoo quoteSummary or web search.

2. **Check history first:** if the candidate is in the `cut` list of `data/tiers.json`,
   it needs a materially stronger case — name what changed since the cut.

3. **Apply the admission bar** (see `docs/tier-framework.md`):
   - Core theme fit: AI infrastructure with multi-year contracted revenue
     (HBM LTAs, backlog, RPO) preferred; "not so cyclical".
   - Compare against the *weakest current member* of the target tier — admission to
     Tier 1 means it would rank above at least the bottom seats, not just "is good".
   - Levels discipline: compute A1 (7-session low) / A2 (35-session low), distance to
     1-yr high, upside-vs-downside ratio. No base (A2 within 3% of A1) → junior flag
     or Tier 2 at best.
   - New/volatile names enter as **junior** (half tranches) regardless of conviction.

4. **Verdict:** `ADMIT Tier 1 (rank N, junior?)` / `ADMIT Tier 2` / `REJECT`, with a
   3–5 bullet rationale and the entry levels.

5. **On admit, persist:**
   - Add the entry to `data/tiers.json` (keep schema: ticker, rank for tier 1,
     junior/probation flags, note with entry levels) and bump `updated`.
   - Remind the user (or do it if asked) that the **cloud routine prompts embed the
     ticker lists** — the Daily Tier-1 routine (`trig_01JgehigiHA3muyMddJwTXLa`) and
     Midday Summary (`trig_01MpR9wRC5xtKQachnyQbbs9`) must be updated via `/schedule`
     for the new name to appear in scheduled reports.
   - Do not commit/push unless asked.
