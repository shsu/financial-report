# Data sources & gotchas

Verified 2026-06-11. Re-verify with `scripts/check-data-sources.sh` when something breaks.

## Alpaca Market Data API (primary)

Auth headers on every call (keys in `~/.claude.json` → `mcpServers.alpaca.env`):

```
-H "APCA-API-KEY-ID: ${ALPACA_API_KEY}" -H "APCA-API-SECRET-KEY: ${ALPACA_SECRET_KEY}"
```

**Guardrail: this key is for `data.alpaca.markets` only.** Never call
`api.alpaca.markets` / `paper-api.alpaca.markets`; never touch orders, account,
positions, or watchlist endpoints from automation.

### Endpoints

- Snapshots (latest trade/quote + today vs prev daily bar):
  `GET /v2/stocks/snapshots?symbols=AAA,BBB`
- Bars: `GET /v2/stocks/bars?symbols=...&timeframe=1Week&adjustment=split&start=YYYY-MM-DD&limit=10000`
- Options chain w/ open interest: `GET /v1beta1/options/snapshots/{UNDERLYING}?feed=indicative&limit=1000&expiration_date_gte=...&expiration_date_lte=...`
- Crypto: `GET /v1beta3/crypto/us/snapshots?symbols=BTC/USD`

### Gotchas (each one cost a debugging session)

1. **`feed=sip` → HTTP 403, always.** The key is on the free data plan with no SIP
   entitlement. Omit the `feed` param (default works) or use `feed=iex`.
   `feed=indicative` on the options endpoint is correct and works.
2. **Multi-symbol bar responses paginate even under the `limit`.** Loop
   `page_token=<next_page_token>` until null and merge pages, or symbols silently
   drop from the response (KGC/MRVL/NOW/RDDT/VRT got cut on first attempt).
   `scripts/fetch-bars-stats.sh` does this correctly.
3. **Always `adjustment=split`.** Known splits that corrupt unadjusted history:
   NOW 5:1 (Dec 2025), NFLX (2025), 0050 4:1 (TWSE, mid-2025).
4. **Ticker collisions.** Alpaca returns *some* fund for `QQC` (~$22 US fund) — it is
   NOT Invesco's TSX-listed NASDAQ-100 CAD ETF. Rule: any TSX/TWSE listing must be
   priced from a Canadian/Taiwanese source, never by feeding the bare ticker to Alpaca.

## Non-US listings (Alpaca has nothing)

- TSX ETFs (XCHP, XEG, ZGLD, QQC, CACE, CAUV, FCCV): Yahoo chart API with `.TO`
  suffix (e.g. `XCHP.TO`), or stockanalysis.com / TMX pages.
- Taiwan (0050, 2330=TSM ADR, 2454=MediaTek): Yahoo `.TW` suffix or TW finance sites.
  2454 has no US listing at all.

## Yahoo (secondary; keyless)

Always send `-H "User-Agent: Mozilla/5.0"` and `--max-time 15`.

- Chart API: `https://query1.finance.yahoo.com/v8/finance/chart/{SYMBOL}?range=5d&interval=1d`
  Symbols used: `^GSPC ^IXIC ^VIX CL=F GC=F NQ=F ES=F ZN=F ^TWII ^KS11 XCHP.TO 2YY=F`
- quoteSummary (fundamentals: forward P/E, PEG, gross margin, earnings calendar)
  requires the cookie+crumb dance:
  1. `curl -s -c /tmp/yc.txt -H "User-Agent: Mozilla/5.0" "https://fc.yahoo.com" > /dev/null`
  2. `CRUMB=$(curl -s -b /tmp/yc.txt -H "User-Agent: Mozilla/5.0" "https://query1.finance.yahoo.com/v1/test/getcrumb")`
  3. `curl -s -b /tmp/yc.txt -H "User-Agent: Mozilla/5.0" "https://query1.finance.yahoo.com/v10/finance/quoteSummary/{SYM}?modules=defaultKeyStatistics,financialData,calendarEvents,earningsTrend&crumb=$CRUMB"`
  Works from residential IPs; datacenter IPs may get blocked — fall back to web search
  per ticker rather than guessing.
- Options fallback: `https://query2.finance.yahoo.com/v7/finance/options/{SYMBOL}`

## 2-year Treasury yield

- **FRED `fredgraph.csv?id=DGS2` has been returning HTTP 504** (their load balancer)
  as of 2026-06-11. Treat FRED as fallback only, with `--max-time 10`.
- Primary substitute: Yahoo chart `2YY=F` (CME 2-yr yield future). Thin market, can
  print stale (showed 3.8 vs ~5% spot once) — always cross-check against a web search
  and prefer the search figure if they disagree by > 0.1.

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

## FX rule of thumb

CAD→USD conversion costs ~1–2% retail. That dwarfs ETF fee differences
(2.5–5 years of a 0.40% MER), so for new CAD cash a TSX-listed wrapper beats
converting to buy the cheaper US-listed equivalent — even when the US version is
otherwise strictly better.
