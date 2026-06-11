# Swing-Trading Local Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Local-first swing-trading position awareness: a trade journal (`data/trades.json`), derived positions + indicator math in bash/jq scripts, and three Claude Code skills (log-trade, swing-status, swing-alerts).

**Architecture:** Append-only `data/trades.json` is the single source of truth; positions are always derived by `scripts/positions.sh` (average-cost method). `scripts/lib/indicators.jq` holds the pure math (ATR/RSI/SMA/relative volume/A1/A2), wrapped by `scripts/indicators.sh` which fetches bars from Alpaca (US) and Yahoo (`.TO`/`.TW`). Skills are markdown instructions that orchestrate the scripts. Cloud routines are NOT touched.

**Tech Stack:** bash + jq + curl (matches existing `scripts/` conventions: keys from `~/.claude.json`, `--max-time`, loud failures). Tests are plain bash scripts; offline tests use generated fixtures.

**Repo:** `~/code/financial-report` (work on `main`; push after each task). Spec: `docs/superpowers/specs/2026-06-11-swing-trading-local-design.md`.

**Conventions for every task:** macOS bash (no GNU-only flags: no `grep -P`, use `date -v`), `set -euo pipefail` in scripts, commit messages end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

## File structure

| Path | Responsibility |
|---|---|
| `data/trades.json` | Append-only journal; written ONLY by log-trade skill |
| `scripts/positions.sh` | trades.json → per-ticker/account positions TSV (qty, avg cost, realized P&L, latest stop/target) |
| `scripts/lib/indicators.jq` | Pure math: ATR14, RSI14, SMA20/50, relative volume, A1, A2 from a bar array |
| `scripts/indicators.sh` | Symbol list → fetch bars (Alpaca US / Yahoo .TO .TW) → apply indicators.jq → TSV |
| `tests/test-positions.sh` | Offline fixture test for positions.sh |
| `tests/test-indicators.sh` | Offline generated-fixture test for indicators.jq |
| `tests/smoke-indicators.sh` | Live network smoke test (manual, 2 symbols) |
| `tests/run-tests.sh` | Runs the two offline tests |
| `tests/fixtures/trades-sample.json` | Known trade sequence with hand-computed expected positions |
| `.claude/skills/log-trade/SKILL.md` | Skill: single/bulk/seed trade entry → validate → append → commit+push |
| `.claude/skills/swing-status/SKILL.md` | Skill: on-demand position dashboard |
| `.claude/skills/swing-alerts/SKILL.md` | Skill: trigger evaluation for `/loop 1h` |
| `docs/data-sources.md` (modify) | Add Alpaca News API + TradingView scanner sections |
| `README.md` (modify) | Add new files/skills to layout + skills sections |

---

### Task 1: positions.sh (derived positions, average-cost)

**Files:**
- Create: `tests/fixtures/trades-sample.json`
- Create: `tests/test-positions.sh`
- Create: `scripts/positions.sh`

- [ ] **Step 1: Write the fixture**

`tests/fixtures/trades-sample.json` — covers seed, DCA (avg-cost blend), partial sell (realized P&L, avg unchanged), full exit, multi-account, multi-currency:

```json
{ "trades": [
  { "id": "2026-06-01-001", "date": "2026-06-01", "ticker": "MU",   "side": "buy",  "qty": 10,  "price": 800,  "currency": "USD", "account": "ibkr-usd", "setup": "seed",  "stop": 750 },
  { "id": "2026-06-02-001", "date": "2026-06-02", "ticker": "MU",   "side": "buy",  "qty": 10,  "price": 900,  "currency": "USD", "account": "ibkr-usd", "setup": "DCA",   "stop": 820, "target": 1000 },
  { "id": "2026-06-05-001", "date": "2026-06-05", "ticker": "MU",   "side": "sell", "qty": 10,  "price": 950,  "currency": "USD", "account": "ibkr-usd", "setup": "trim" },
  { "id": "2026-06-01-002", "date": "2026-06-01", "ticker": "XCHP", "side": "buy",  "qty": 100, "price": 130,  "currency": "CAD", "account": "tfsa-cad", "setup": "seed" },
  { "id": "2026-06-03-001", "date": "2026-06-03", "ticker": "DRAM", "side": "buy",  "qty": 20,  "price": 55,   "currency": "USD", "account": "ibkr-usd", "setup": "junior-tranche" },
  { "id": "2026-06-08-001", "date": "2026-06-08", "ticker": "DRAM", "side": "sell", "qty": 20,  "price": 60,   "currency": "USD", "account": "ibkr-usd", "setup": "exit-target" }
] }
```

Hand-computed expectations: MU → qty 10, avg 850 ((10·800+10·900)/20), realized 1000 (10·(950−850)), stop 820, target 1000, open. XCHP → qty 100, avg 130, realized 0, open. DRAM → qty 0, avg 55, realized 100, closed.

- [ ] **Step 2: Write the failing test**

`tests/test-positions.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(scripts/positions.sh tests/fixtures/trades-sample.json)
expect() {
  echo "$OUT" | grep -qF "$(printf "$1")" || { echo "FAIL missing: $1"; echo "--- got:"; echo "$OUT"; exit 1; }
}
expect 'MU\tibkr-usd\tUSD\t10\t850\t1000\t820\t1000\topen'
expect 'XCHP\ttfsa-cad\tCAD\t100\t130\t0\t-\t-\topen'
expect 'DRAM\tibkr-usd\tUSD\t0\t55\t100\t-\t-\tclosed'
echo "PASS test-positions"
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd ~/code/financial-report && chmod +x tests/test-positions.sh && tests/test-positions.sh`
Expected: FAIL — `scripts/positions.sh: No such file or directory`

- [ ] **Step 4: Implement scripts/positions.sh**

```bash
#!/usr/bin/env bash
# Derive positions from the trade journal. Average-cost method (matches Canadian
# ACB convention). Columns: ticker account currency qty avg_cost realized_pnl
# stop target state. Positions are ALWAYS derived - never stored.
# Usage: positions.sh [trades.json]   (default: data/trades.json)
set -euo pipefail
TRADES="${1:-data/trades.json}"

jq -re '
  def round2: . * 100 | round / 100;
  .trades
  | sort_by(.date, .id)
  | group_by(.ticker + "|" + .account)
  | map(
      reduce .[] as $t (
        { ticker: .[0].ticker, account: .[0].account, currency: .[0].currency,
          qty: 0, avg: 0, realized: 0, stop: null, target: null };
        if $t.side == "buy" then
          .avg = ((.avg * .qty + $t.price * $t.qty) / (.qty + $t.qty))
          | .qty += $t.qty
        elif $t.side == "sell" then
          .realized += ($t.qty * ($t.price - .avg))
          | .qty -= $t.qty
        else error("unknown side: \($t.side)") end
        | .stop   = ($t.stop   // .stop)
        | .target = ($t.target // .target)
      )
    )
  | map(if .qty < 0 then error("negative position for \(.ticker)/\(.account) - bad journal") else . end)
  | .[]
  | [ .ticker, .account, .currency, .qty, (.avg|round2), (.realized|round2),
      (.stop // "-"), (.target // "-"),
      (if .qty > 0 then "open" else "closed" end) ]
  | @tsv
' "$TRADES"
```

- [ ] **Step 5: Run test to verify it passes**

Run: `chmod +x scripts/positions.sh && tests/test-positions.sh`
Expected: `PASS test-positions`

- [ ] **Step 6: Negative-position guard check**

Run: `jq '.trades += [{"id":"2026-06-09-001","date":"2026-06-09","ticker":"XCHP","side":"sell","qty":999,"price":140,"currency":"CAD","account":"tfsa-cad","setup":"other"}]' tests/fixtures/trades-sample.json > /tmp/bad-trades.json && scripts/positions.sh /tmp/bad-trades.json; echo "exit=$?"`
Expected: error message mentioning `negative position for XCHP/tfsa-cad`, `exit=5` (jq error exit; any non-zero acceptable)

- [ ] **Step 7: Commit**

```bash
git add scripts/positions.sh tests/test-positions.sh tests/fixtures/trades-sample.json
git commit -m "feat: positions.sh - derive positions from trade journal (avg-cost)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: indicator math (indicators.jq) + fetch wrapper (indicators.sh)

**Files:**
- Create: `scripts/lib/indicators.jq`
- Create: `tests/test-indicators.sh`
- Create: `scripts/indicators.sh`
- Create: `tests/smoke-indicators.sh`

- [ ] **Step 1: Write the failing math test (generated fixtures, offline)**

`tests/test-indicators.sh` — constant series (ATR 0, RSI 50) and linear ramp (ATR 2, RSI 100), values hand-derivable:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
jq -n '[range(0;60) | {t: ., o:100, h:100, l:100, c:100, v:1000}]' > /tmp/bars-const.json
jq -n '[range(0;60) | {t: ., o:(100+.), h:(101+.), l:(99+.), c:(100+.), v:1000}]' > /tmp/bars-ramp.json
C=$(jq -r -L scripts/lib 'include "indicators"; indicators | @tsv' /tmp/bars-const.json)
R=$(jq -r -L scripts/lib 'include "indicators"; indicators | @tsv' /tmp/bars-ramp.json)
# columns: last_close atr14 rsi14 sma20 sma50 relvol a1 a2
[ "$C" = "$(printf '100\t0\t50\t100\t100\t1\t100\t100')" ]   || { echo "FAIL const: [$C]"; exit 1; }
[ "$R" = "$(printf '159\t2\t100\t149.5\t134.5\t1\t152\t124')" ] || { echo "FAIL ramp: [$R]"; exit 1; }
echo "PASS test-indicators"
```

Ramp expectations: closes 100..159 → last 159; TR is always 2 → ATR14 = 2; all deltas +1 → RSI 100; SMA20 = mean(140..159) = 149.5; SMA50 = mean(110..159) = 134.5; relvol = 1; A1 = min(low last 7) = 159−7+1−1 = 152; A2 = min(low last 35) = 125−1 = 124.

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x tests/test-indicators.sh && tests/test-indicators.sh`
Expected: FAIL — `include "indicators"` cannot find module

- [ ] **Step 3: Implement scripts/lib/indicators.jq**

```jq
# Pure indicator math. Input: array of bars {t,o,h,l,c,v} sorted ascending,
# >= 51 bars. Output: [last_close, atr14, rsi14, sma20, sma50, relvol, a1, a2].
# Simplifications (documented): ATR = simple mean of last 14 true ranges (not
# Wilder smoothing); RSI = simple mean gains/losses over last 14 deltas.
def abs2: if . < 0 then -. else . end;
def round2: . * 100 | round / 100;

def indicators:
  . as $b
  | ($b | length) as $n
  | (if $n < 51 then error("insufficient bars: \($n) < 51") else . end)
  | ($b | map(.c)) as $c
  | ([range(1; $n) | [ ($b[.].h - $b[.].l),
                       (($b[.].h - $c[. - 1]) | abs2),
                       (($b[.].l - $c[. - 1]) | abs2) ] | max]) as $tr
  | ($tr[-14:] | add / 14) as $atr
  | ([range($n - 14; $n) | $c[.] - $c[. - 1]]) as $d
  | ($d | map(if . > 0 then . else 0 end) | add / 14) as $gain
  | ($d | map(if . < 0 then -. else 0 end) | add / 14) as $loss
  | (if $loss == 0 then (if $gain == 0 then 50 else 100 end)
     else 100 - (100 / (1 + ($gain / $loss))) end) as $rsi
  | ($c[-20:] | add / 20) as $sma20
  | ($c[-50:] | add / 50) as $sma50
  | ($b | map(.v)) as $v
  | (if ($v[-21:-1] | add) == 0 then 0
     else $v[-1] / (($v[-21:-1] | add) / 20) end) as $relvol
  | ($b[-7:]  | map(.l) | min) as $a1
  | ($b[-35:] | map(.l) | min) as $a2
  | [ $c[-1], ($atr|round2), ($rsi|round), ($sma20|round2), ($sma50|round2),
      ($relvol|round2), $a1, $a2 ];
```

- [ ] **Step 4: Run math test to verify it passes**

Run: `tests/test-indicators.sh`
Expected: `PASS test-indicators`

- [ ] **Step 5: Implement scripts/indicators.sh (fetch wrapper)**

```bash
#!/usr/bin/env bash
# Indicators for a symbol list. US symbols via Alpaca daily bars (split-adjusted,
# paginated, NO feed=sip - 403 on this plan). Symbols ending .TO or .TW via Yahoo
# chart API. Output TSV: symbol last atr14 rsi14 sma20 sma50 relvol a1 a2
# Usage: indicators.sh "NVDA,MU,XCHP.TO"
set -euo pipefail
SYMS="${1:?usage: indicators.sh SYM1,SYM2,...   (.TO/.TW suffix for TSX/Taiwan)}"
cd "$(dirname "$0")/.."

if [ -z "${ALPACA_API_KEY:-}" ]; then
  ALPACA_API_KEY=$(jq -r '.mcpServers.alpaca.env.ALPACA_API_KEY' ~/.claude.json)
  ALPACA_SECRET_KEY=$(jq -r '.mcpServers.alpaca.env.ALPACA_SECRET_KEY' ~/.claude.json)
fi
START=$(date -v-150d +%Y-%m-%d 2>/dev/null || date -d '150 days ago' +%Y-%m-%d)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

US=$(echo "$SYMS" | tr ',' '\n' | grep -v '\.' | paste -sd, - || true)
FOREIGN=$(echo "$SYMS" | tr ',' '\n' | grep '\.' || true)

echo '{}' > "$TMP/bars.json"
if [ -n "$US" ]; then
  TOKEN=""
  for _ in $(seq 1 20); do
    URL="https://data.alpaca.markets/v2/stocks/bars?symbols=$US&timeframe=1Day&adjustment=split&start=$START&limit=10000"
    [ -n "$TOKEN" ] && URL="$URL&page_token=$TOKEN"
    curl -s --max-time 30 "$URL" \
      -H "APCA-API-KEY-ID: $ALPACA_API_KEY" -H "APCA-API-SECRET-KEY: $ALPACA_SECRET_KEY" > "$TMP/page.json"
    jq -s '.[0] as $acc | .[1].bars | to_entries
           | reduce .[] as $e ($acc; .[$e.key] = ((.[$e.key] // []) + $e.value))' \
      "$TMP/bars.json" "$TMP/page.json" > "$TMP/bars2.json" && mv "$TMP/bars2.json" "$TMP/bars.json"
    TOKEN=$(jq -r '.next_page_token // empty' "$TMP/page.json")
    [ -z "$TOKEN" ] && break
  done
fi
for F in $FOREIGN; do
  curl -s --max-time 15 -H "User-Agent: Mozilla/5.0" \
    "https://query1.finance.yahoo.com/v8/finance/chart/$F?range=8mo&interval=1d" > "$TMP/y.json"
  jq -s --arg s "$F" '.[0] as $acc | .[1].chart.result[0] as $r
    | $acc + { ($s): ([range(0; $r.timestamp|length)
        | { t: $r.timestamp[.], o: $r.indicators.quote[0].open[.],
            h: $r.indicators.quote[0].high[.], l: $r.indicators.quote[0].low[.],
            c: $r.indicators.quote[0].close[.], v: $r.indicators.quote[0].volume[.] }]
        | map(select(.c != null))) }' "$TMP/bars.json" "$TMP/y.json" > "$TMP/bars2.json" \
    && mv "$TMP/bars2.json" "$TMP/bars.json"
done

echo -e "symbol\tlast\tatr14\trsi14\tsma20\tsma50\trelvol\ta1\ta2"
jq -r -L scripts/lib 'include "indicators";
  to_entries[] | [.key] + (.value | sort_by(.t) | indicators) | @tsv' "$TMP/bars.json"

GOT=$(jq -r 'keys | join(",")' "$TMP/bars.json")
for S in $(echo "$SYMS" | tr ',' ' '); do
  echo "$GOT" | tr ',' '\n' | grep -qx "$S" || { echo "ERROR: no data for $S" >&2; exit 1; }
done
```

- [ ] **Step 6: Live smoke test (network required)**

`tests/smoke-indicators.sh`:

```bash
#!/usr/bin/env bash
# Live network smoke test - run manually, not part of run-tests.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(scripts/indicators.sh "NVDA,XCHP.TO")
echo "$OUT"
[ "$(echo "$OUT" | wc -l | tr -d ' ')" = "3" ] || { echo "FAIL: expected header + 2 rows"; exit 1; }
echo "$OUT" | tail -2 | awk -F'\t' 'NF != 9 { print "FAIL: row with " NF " cols"; exit 1 }'
echo "PASS smoke-indicators"
```

Run: `chmod +x scripts/indicators.sh tests/smoke-indicators.sh && tests/smoke-indicators.sh`
Expected: `PASS smoke-indicators` with populated numeric columns for both symbols.

- [ ] **Step 7: Create tests/run-tests.sh and run it**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
./test-positions.sh
./test-indicators.sh
echo "ALL OFFLINE TESTS PASS"
```

Run: `chmod +x tests/run-tests.sh && tests/run-tests.sh`
Expected: `ALL OFFLINE TESTS PASS`

- [ ] **Step 8: Commit**

```bash
git add scripts/lib/indicators.jq scripts/indicators.sh tests/test-indicators.sh tests/smoke-indicators.sh tests/run-tests.sh
git commit -m "feat: indicator math (ATR/RSI/SMA/relvol/A1/A2) + Alpaca/Yahoo fetch wrapper

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: trades.json + log-trade skill

**Files:**
- Create: `data/trades.json`
- Create: `.claude/skills/log-trade/SKILL.md`

- [ ] **Step 1: Create the empty journal**

`data/trades.json`:

```json
{
  "$schema_note": "Append-only trade journal - the single source of truth for positions, which are ALWAYS derived via scripts/positions.sh and never stored. Written ONLY by the log-trade skill. Fields per trade: id (date-NNN), date, ticker, side (buy|sell), qty, price, currency, account, setup (A1-buy|DCA|junior-tranche|breakout|trim|exit-stop|exit-target|seed|other), thesis?, stop?, target?.",
  "trades": []
}
```

Validate: `jq -e '.trades | length == 0' data/trades.json` → `true`

- [ ] **Step 2: Write .claude/skills/log-trade/SKILL.md**

```markdown
---
name: log-trade
description: Record swing trades into data/trades.json - single trades in plain English ("bought 10 MU at 858.50 in IBKR, stop 820"), bulk import of pasted fills/CSV/broker confirmations, or seeding current holdings. Validates, previews, appends, auto-commits and pushes. Use when the user says "log trade", "bought/sold X", "import trades", or "seed my positions".
---

# Log Trade

Sole writer of `data/trades.json`. Every path ends: validate -> preview -> append ->
auto-commit + push. Positions are derived, never edited directly.

## Input modes

1. **Single trade, plain English.** Parse ticker, side, qty, price; optional stop,
   target, thesis, account, date (default today), setup. "sold half my DRAM" /
   "sold all" resolve against the current position from `scripts/positions.sh`.
   Defaults: account inferred from currency when unambiguous (USD -> ibkr-usd,
   CAD -> tfsa-cad, TWD -> tw-broker - confirm first use and reuse); setup
   suggested from context but always shown for correction.
2. **Bulk import.** User pastes anything (lines, CSV, broker confirmation text).
   Parse every fill found; show ONE preview table (date, ticker, side, qty, price,
   currency, account, setup); single confirmation; append all. List unparseable
   lines verbatim - never guess them.
3. **Seed mode.** "seed my positions: 10 MU @ 858, 100 XCHP @ 131 CAD tfsa" ->
   one trade per holding with setup "seed", price = average cost, date = today
   unless given. This bootstraps the book without history.

## Procedure

1. Parse input into candidate trade objects (schema in data/trades.json header).
2. Validate each: qty > 0; price > 0; side in buy|sell; selling more than the
   currently held qty requires explicit user confirmation; ticker missing from
   every tier in data/tiers.json -> warn but allow.
3. Show the preview table and get one confirmation (AskUserQuestion or plain
   chat confirm; skip the question only if the user already gave an unambiguous
   complete instruction in this turn).
4. Assign ids: `YYYY-MM-DD-NNN`, NNN = next free integer for that date.
5. Append atomically: build the new file with jq into a temp file, `jq -e .`
   validate, `scripts/positions.sh /tmp/newfile` must exit 0 (catches negative
   positions), then move into place.
6. Echo the updated derived position lines for the affected tickers.
7. `git add data/trades.json && git commit` (message: "journal: <summary>",
   end with the Claude co-author line) `&& git push`. Push failure = warn only.
```

- [ ] **Step 3: Validate skill frontmatter parses**

Run: `head -5 .claude/skills/log-trade/SKILL.md | grep -c '^name: log-trade\|^---'`
Expected: `3` (two `---` lines + name line). Also `jq -e . data/trades.json` → exits 0.

- [ ] **Step 4: Commit**

```bash
git add data/trades.json .claude/skills/log-trade/SKILL.md
git commit -m "feat: trade journal + log-trade skill (single/bulk/seed modes)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: swing-status skill

**Files:**
- Create: `.claude/skills/swing-status/SKILL.md`

- [ ] **Step 1: Write .claude/skills/swing-status/SKILL.md**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/swing-status/SKILL.md
git commit -m "feat: swing-status skill (position dashboard)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: swing-alerts skill

**Files:**
- Create: `.claude/skills/swing-alerts/SKILL.md`

- [ ] **Step 1: Write .claude/skills/swing-alerts/SKILL.md**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/swing-alerts/SKILL.md
git commit -m "feat: swing-alerts skill for /loop (stop/floor/target/ATR/gap/news triggers)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: docs updates

**Files:**
- Modify: `docs/data-sources.md` (append two sections before the "FX rule of thumb" section)
- Modify: `README.md` (layout table + skills section)

- [ ] **Step 1: Add to docs/data-sources.md** (insert before `## FX rule of thumb`):

```markdown
## Alpaca News API

`GET https://data.alpaca.markets/v1beta1/news?symbols=AAA,BBB&start=<ISO>&limit=50`
with the standard Alpaca auth headers. Free on the existing key (Benzinga-sourced).
Used by swing-alerts for held-name headlines; available to any report as
first-line news before web search.

## TradingView (optional cross-check - unofficial, fragile)

There is NO official TradingView API; community TradingView MCPs wrap the
unofficial scanner endpoint and break without notice. We compute indicators
ourselves (`scripts/indicators.sh`). If a TA-rating cross-check is ever wanted:

    curl -s 'https://scanner.tradingview.com/america/scan' \
      -H 'Content-Type: application/json' \
      -d '{"symbols":{"tickers":["NASDAQ:NVDA"]},"columns":["Recommend.All","RSI","ATR"]}'

Treat as best-effort only; never a primary source. ToS-gray - do not build on it.
```

- [ ] **Step 2: Update README.md**

Add rows to the layout table (after the `.claude/skills/tier-admission/` row):

```markdown
| `data/trades.json` | Append-only swing-trade journal — positions always derived, never stored |
| `scripts/positions.sh` | trades.json → positions (avg-cost, realized P&L, latest stop/target) |
| `scripts/lib/indicators.jq` + `scripts/indicators.sh` | ATR14/RSI14/SMA/relvol/A1/A2 from Alpaca + Yahoo bars |
| `tests/` | `run-tests.sh` (offline fixture tests) + live smoke test |
| `.claude/skills/log-trade/` | Skill: record trades (single / bulk import / seed current holdings) |
| `.claude/skills/swing-status/` | Skill: on-demand position dashboard (P&L, stops, ATR/RSI, concentration) |
| `.claude/skills/swing-alerts/` | Skill: trigger scan for `/loop 1h` — prints only what fired |
```

Add to the Skills section:

```markdown
- **log-trade / swing-status / swing-alerts** — local-first swing-trading suite
  (see `docs/superpowers/specs/2026-06-11-swing-trading-local-design.md`).
  Typical day: `/loop 1h` invoking swing-alerts while at the desk; `swing-status`
  on demand; every fill logged via log-trade (which auto-commits + pushes).
  Cloud routines deliberately do NOT read positions (Approach C). Email delivery
  TBD pending credentials; PushNotification is the interim alert channel.
```

- [ ] **Step 3: Run offline tests once more**

Run: `tests/run-tests.sh`
Expected: `ALL OFFLINE TESTS PASS`

- [ ] **Step 4: Commit**

```bash
git add docs/data-sources.md README.md
git commit -m "docs: Alpaca News API, TradingView scanner note, swing suite in README

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: End-to-end walkthrough (manual acceptance) + push

- [ ] **Step 1: Walkthrough on a throwaway journal (do NOT touch data/trades.json)**

```bash
cp data/trades.json /tmp/walkthrough.json
jq '.trades += [
  {"id":"WALK-001","date":"2026-06-11","ticker":"MU","side":"buy","qty":5,"price":860,"currency":"USD","account":"ibkr-usd","setup":"seed","stop":820,"target":1000},
  {"id":"WALK-002","date":"2026-06-11","ticker":"XCHP","side":"buy","qty":50,"price":135,"currency":"CAD","account":"tfsa-cad","setup":"seed"}
]' /tmp/walkthrough.json > /tmp/walkthrough2.json && mv /tmp/walkthrough2.json /tmp/walkthrough.json
scripts/positions.sh /tmp/walkthrough.json
scripts/indicators.sh "MU,XCHP.TO"
```

Expected: positions show MU 5 @ 860 (stop 820, target 1000, open) and XCHP 50 @ 135 open; indicators print 2 data rows with all 9 columns populated. Sanity-check by hand that MU's a1/a2 look like plausible recent lows.

- [ ] **Step 2: Verify journal untouched and repo clean of walkthrough artifacts**

Run: `jq -e '.trades | length == 0' data/trades.json && git status --porcelain`
Expected: `true` and empty status (everything committed in Tasks 1–6).

- [ ] **Step 3: Push**

```bash
git push
git log --oneline -7
```

Expected: the six feature/docs commits from Tasks 1–6 on origin/main.

---

## Self-review (completed at planning time)

- **Spec coverage:** trades.json schema → T3; log-trade single/bulk/seed → T3; swing-status → T4; swing-alerts + /loop + PushNotification + email stub → T5; positions.sh avg-cost/realized/negative-guard → T1; indicators math + Alpaca/Yahoo fetch → T2; Alpaca News API + TradingView note → T6 (+ news usage in T5); fixtures/tests → T1/T2; cloud routines untouched → no task touches prompts/ or routines (by design); error handling (atomic append, jq -e, loud missing symbols, skip-not-fire) → T1 S6, T2 S5, T3 S2 step 5, T5 S1 step 6.
- **Placeholder scan:** the email line in T5 is an intentional, spec-mandated stub with explicit behavior ("do nothing for email"), not a TBD.
- **Type consistency:** positions.sh column order (ticker account currency qty avg realized stop target state) matches T1 test and T7 walkthrough; indicators column order (last atr14 rsi14 sma20 sma50 relvol a1 a2) consistent across T2 test, T2 wrapper header, T4/T5 consumers; trades.json field names identical in fixture (T1), schema note (T3), and walkthrough (T7).
