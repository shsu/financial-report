# Tier framework & trading discipline

## Stocks: Tier 1 / Tier 2 / CUT

- **Tier 1** — stable and growing; core theme is AI infrastructure with
  *multi-year contracted revenue* (HBM long-term agreements, backlogs, RPO) =
  "not so cyclical". Ranked list lives in `docs/current-book-*.md`.
- **Tier 2** — watchlist / contrarian / paired trades. Promotion and demotion are
  rule-driven (see conditionals inside `prompts/daily-tier1-report.md`).
- **CUT** — thesis broken or structurally on the wrong side (e.g. seat-based SaaS
  during the 2026 derating).
- **Juniors** — early/volatile Tier-1 names (CRDO, ALAB type) run half tranches,
  always, because of the air gap to their structural supports.

### Levels (recomputed fresh, never cached)

- **A1** "recent floor" = lowest low of the last 7 sessions (flush support).
- **A2** "deeper floor" = lowest low of the last 35 sessions (structural base);
  if within 3% of A1 there is no real base — reduce size.
- **R/R** = (1-yr high − price) / (price − A2).

### Actions

- **BUY NOW**: price ≤ A1 (or within 1%) AND weakness is macro/flow-driven (verify no
  company-specific news) AND macro gate open → deploy 40% tranche, reserve 60% for A2.
- **DCA**: 1–6% above A1 with R/R ≥ 2.5, or basing ≥ 5 sessions → small recurring adds.
- **HOLD**: everything else, including anything within 5% of its 1-yr high. Never chase.
- **Macro gate**: 2-yr yield ≥ 5.0% or VIX > 30 → halve buys (HALF); VIX > 35 →
  all BUY NOW downgrade to DCA (CLOSED).
- **Earnings gate**: reporting within 5 sessions → tranche halved; use the
  option-implied move to decide whether to wait for the print.

## ETFs: Tier 1 / Tier 2 / CUT

Scoring criteria (set June 2026):

1. **Fee**, scaled by what the fee buys. Sub-0.25% passives that complete the
   factor/geography map = Tier 1. Active 0.65–0.75% earns Tier 1 *only* with
   un-replicable exposure (Korea memory, Asian grid names, private sleeves) or a
   proven active record. Mid-priced passives (0.40–0.50%) that merely repackage
   stocks already held as singles = the cut zone.
2. **Active-management bonus** for funds that have delivered (e.g. VistaShares AIS/POW).
3. **No penalty for private/SpaceX-style sleeves** — un-replicable access counts as
   a feature, not a risk deduction.
4. **Overlap budget: max 1–2 funds per cluster** (US growth, US value, Taiwan, etc.).
   The blend fund (broad core ≈ growth fund + value fund) is always the first demotion.
5. **Account/currency override**: a "redundant" local-currency wrapper stays Tier 1
   if it avoids the 1–2% FX conversion (see `docs/data-sources.md`). One slot,
   currency decides who fills it.

### ETF actions

- **BUY** — add now (gated on the day's macro/CPI risk clearing).
- **DCA** — systematic/tiered accumulation. For juniors this means *tiered-support
  adds only*, not calendar buys; for broad cheap funds (0050) calendar DCA is fine.
- **HOLD** — no adds: either overlap with singles, cash at 5% competing, or
  post-run chase risk.
- Daily automation simplifies to BUY|HOLD (see routine prompt): BUY requires ≥4% below
  the 1-yr high AND settling (higher lows over ~2 weeks) AND gate open; juniors need
  ≥10% below the high.

## Style rule for all generated reports

Written for a software engineer, not a finance person: no jargon, plain-English
column headers, every unavoidable term defined in parentheses on first use.
The calculations don't change — only the wording does.
