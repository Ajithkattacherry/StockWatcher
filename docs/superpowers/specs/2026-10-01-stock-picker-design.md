# StockWatcher — Design Spec

**Date:** 2026-10-01
**Status:** Draft, awaiting review
**Author:** Ajith Kattacherry (with Claude)

## 1. Purpose

StockWatcher is an iOS app that helps pick US stocks with strong long-term growth potential. It ranks stocks with a transparent score and explains every company in plain language, using mostly visuals.

### What the user asked for
- P/E ratio for each stock
- An upside estimate
- Insider buying and selling
- What major institutions are doing (holdings and trends), as a "do they trust it" signal
- A top 10 list of suggestions
- An easy-to-understand report on each company's financials

### Agreed constraints
| Constraint | Decision |
|---|---|
| Audience | Personal use now; small private group (friends and family) next; App Store later |
| Data budget | $0 per month |
| Market | US stocks only |
| Freshness | Daily (after market close), not real-time |
| Universe | S&P 500 plus a user-editable watchlist |
| Investing style | Long-term growth (3–5+ years) |
| Report style | Visual-first, with an on-device AI summary and a template fallback |
| Minimum OS | Latest iOS (Apple Intelligence for AI summaries; template fallback elsewhere) |

### Success criteria
1. Opening the app shows a fresh top 10 within 1 second, from cache.
2. Every ranked stock shows why it ranked, in one line.
3. Every number in the report traces back to a named source (SEC filing or price API).
4. Adding a watchlist ticker produces a full report on the phone in under 30 seconds.
5. Running cost stays at $0 per month.

### Non-goals (v1)
- Real-time prices or intraday alerts
- Buy/sell recommendations or brokerage integration
- Analyst price targets (not available for $0)
- Non-US stocks, ETFs, options, crypto
- User accounts or sync between devices
- Adjustable scoring weights (planned later; see §11)

## 2. Architecture

One repo, three parts, with the shared scoring logic in a Swift package.

```
StockWatcher/
├── StockCore/        Swift package: models, data sources, scoring (no UI)
├── Pipeline/         Swift CLI, run nightly by GitHub Actions
├── StockApp/         SwiftUI iOS app
└── .github/workflows/nightly.yml
```

### 2.1 StockCore (Swift package, iOS + Linux)
Everything that must behave identically in the app and the pipeline.

- **Models:** `Company`, `FinancialSnapshot`, `PriceQuote`, `InsiderTransaction`, `InstitutionalPosition`, `ScoreBreakdown`, `UpsideScenario`, `StockReport`.
- **Data source protocols:** `FundamentalsSource`, `PriceSource`, `InsiderSource`, `HoldingsSource`. v1 implementations: `EDGARFundamentalsSource`, `EDGARInsiderSource`, `FinnhubPriceSource`, `PublishedHoldingsSource` (reads the pipeline's JSON). A paid provider later is one new conformance.
- **`ScoringEngine`:** a pure function, `(CompanyInputs, PercentileTable) -> ScoreBreakdown`. No networking or I/O.
- **`UpsideCalculator`:** pure; produces the two scenarios in §4.3.
- **`RateLimiter`:** an actor that caps EDGAR calls at 8 per second.
- **`HTTPClient`:** a thin wrapper over `URLSession` that sets the SEC User-Agent and retries with backoff.

### 2.2 Pipeline (Swift CLI)
Runs every weekday at 22:30 UTC (after US market close) on GitHub Actions.

1. Load the S&P 500 constituent list (refreshed weekly from a public source; cached in the repo).
2. For each company: fetch EDGAR facts and Form 4 filings, and the Finnhub quote and P/E.
3. Quarterly only: download the SEC 13F data set, map CUSIP to ticker, and build per-ticker holdings history.
4. Compute the percentile table across the S&P 500.
5. Score every company and pick the top 10.
6. Write the JSON outputs (§5) and publish them to GitHub Pages.

Secrets: `FINNHUB_API_KEY` and `SEC_USER_AGENT` live in GitHub Secrets.

### 2.3 StockApp (SwiftUI)
- Downloads the nightly JSON, caches it with SwiftData, and works offline.
- Scores watchlist tickers on the phone with `StockCore`, using the published percentile table and holdings so scores are comparable.
- `Summarizer` protocol: `FoundationModelsSummarizer` (Apple's on-device model) and `TemplateSummarizer` (fallback).
- The user's own Finnhub key is entered in Settings and stored in the Keychain; it is only used for on-phone watchlist scoring.

### 2.4 Data flow
```
Nightly:   GitHub Actions → Pipeline → EDGAR + Finnhub (+13F quarterly)
                        → top10.json, reports/*.json, percentiles.json, holdings/*.json
                        → GitHub Pages

App open:  StockApp → GitHub Pages → SwiftData cache → Top 10 screen

Watchlist: StockApp → StockCore → EDGAR + Finnhub (+ published holdings/percentiles)
                    → ScoreBreakdown → Summarizer → Report screen
```

## 3. Data sources

| Data | Source | Access | Limits and notes |
|---|---|---|---|
| Financial statements | SEC EDGAR `data.sec.gov/api/xbrl/companyfacts/CIK##########.json` | Free, no key | 10 requests/sec, User-Agent required |
| Ticker → CIK | `sec.gov/files/company_tickers.json` | Free | Cache daily |
| Insider trades | EDGAR submissions API + Form 4 XML | Free | Same limits |
| Institutional holdings | SEC Form 13F data sets (quarterly zips, ~70 MB) | Free | ~45-day lag after quarter end; pipeline only |
| Price, P/E | Finnhub free tier (`/quote`, `/stock/metric`) | Free key | 60 calls/min, personal use only |
| S&P 500 list | Public constituents list | Free | Refresh weekly |

### Rules
- EDGAR calls are capped at 8/sec by `RateLimiter`. On a 403 or 429, back off exponentially (starting at 10 s) and resume.
- Finnhub calls are paced at 55/min. If the budget runs out, use the previous night's price and mark it stale.
- Revenue uses a fallback list of XBRL tags: `RevenueFromContractWithCustomerExcludingAssessedTax`, `Revenues`, `SalesRevenueNet`, `RevenueFromContractWithCustomerIncludingAssessedTax`. The first tag with annual 10-K data covering the last 4 fiscal years wins.
- Insider trades count only open-market purchases (code `P`) and sales (code `S`). Sales under a 10b5-1 plan are excluded from the sell signal. Grants and option exercises are ignored.
- 13F: positions are aggregated by CUSIP per quarter. CUSIP → ticker uses the 13F securities list joined against EDGAR names. Unmapped tickers get no holdings data (see §8).

### Licensing note
Finnhub's free tier is for personal use. Before sharing with friends and family, confirm the terms or move to a paid tier. Before the App Store, a provider with redistribution rights is required. SEC data is public domain.

## 4. Scoring

### 4.1 Growth Score (0–100)
Each metric is converted to a percentile against the S&P 500. Each part is the average of its metrics' percentiles. The final score is the weighted sum.

| Part | Weight | Metrics |
|---|---|---|
| Growth | 40% | 3-year revenue CAGR; 3-year EPS CAGR (operating income CAGR if EPS ≤ 0 at the start); acceleration = latest-year growth minus 3-year CAGR |
| Smart money | 30% | Net open-market insider buying ($, 6 months), +10 percentile bonus if ≥3 distinct insiders bought; change in total 13F shares held, quarter over quarter; change in number of 13F holders |
| Quality | 20% | Operating-margin trend (3-year change); free-cash-flow margin; net debt ÷ free cash flow (lower is better) |
| Valuation | 10% | PEG = P/E ÷ 3-year EPS CAGR (lower is better; n/a if either is ≤ 0) |

- A part with no usable metrics is left out and the remaining weights are renormalized.
- Scores are rounded to whole numbers.

### 4.2 Top 10 eligibility
- Data for at least 3 of the 4 parts.
- Excluded if both latest annual net income and free cash flow are negative.
- Banks, insurers and REITs (by SIC code) get a "limited data" badge and are excluded from the top 10 in v1.
- Ties are broken by the Growth part score.
- Each pick carries a one-line "reason" built from its two highest-percentile metrics, for example "Top 6% revenue growth · 3 insiders bought in August."

### 4.3 Upside scenarios (3 years)
Not a prediction. Shown as two clearly labeled scenarios with their assumptions.

- `g` = 3-year EPS CAGR, capped at 25%, tapering by 20% each year (e.g. 25% → 20% → 16%).
- **If growth continues:** price₃ = EPS × Π(1+gᵢ) × current P/E.
- **If it gets cheaper:** price₃ = EPS × Π(1+gᵢ) × sector-median P/E.
- Upside % = price₃ ÷ current price − 1.
- Not shown if EPS ≤ 0; the report says why.

### 4.4 Percentile table
The pipeline publishes `percentiles.json` with the S&P 500 distribution of every metric (101 cut points each). The phone uses it to score watchlist stocks on the same scale.

## 5. Published data (GitHub Pages)

| File | Contents | Updated |
|---|---|---|
| `meta.json` | Schema version, generated time, data dates | Nightly |
| `top10.json` | Ranked list: ticker, name, score, reason | Nightly |
| `reports/{TICKER}.json` | Full `StockReport` for each S&P 500 stock | Nightly |
| `percentiles.json` | Metric distributions | Nightly |
| `holdings/{TICKER}.json` | 8 quarters of 13F aggregates, for every mappable ticker | Quarterly |
| `sectors.json` | Sector-median P/E | Nightly |

All files carry `schemaVersion`. The app refuses a higher major version and shows "Update the app to see new data."

## 6. App screens

Tabs: **Top 10**, **Watchlist**, **Settings**.

### 6.1 Top 10
- Rows: rank, score circle, ticker, name, one-line reason, "Watchlist" tag where relevant.
- Header shows when data was generated. Pull to refresh.
- Score colors: 80+ green, 60–79 amber, under 60 gray. Red is never used for scores.

### 6.2 Stock report (shared by Top 10 and Watchlist)
1. Header: score circle, ticker, name, price, P/E, sector, data date.
2. AI summary card (3–4 sentences).
3. Score breakdown: four bars with values; tapping a bar shows its metrics and percentiles.
4. 3-year scenarios: two cards with an expandable "Assumptions" section.
5. Smart money: insider trade timeline (6 months) and fund holdings trend (8 quarters), with the 13F lag noted.
6. Financials: Swift Charts for revenue, EPS, operating margin, free cash flow and net debt, each with a one-line caption ("Revenue has grown every year for 4 years").
7. Footer: sources, "Not investment advice."

### 6.3 Watchlist
- Search by ticker or name (EDGAR ticker list). Add or remove.
- Each row shows score and a "nightly" or "scored just now" label.
- S&P 500 tickers use the nightly report; others are scored on the phone.

### 6.4 Settings
- Finnhub API key (Keychain), with a link to get a free key.
- Data freshness and last-sync time.
- "About the score": a page explaining parts, weights and scenarios.

## 7. AI summary

- Input: a `SummaryFacts` struct of 8–12 computed facts (numbers already formatted). Never raw filings.
- Instructions: rewrite the facts in plain English, 3–4 sentences, no new numbers, no advice.
- **Number check:** every number in the output must match a number in `SummaryFacts` (after normalizing %, $, commas and rounding). Any mismatch, error or unavailable model → `TemplateSummarizer`.
- Summaries are cached per ticker per data date.

## 8. Error handling

| Failure | Behavior |
|---|---|
| Pipeline run fails | App shows last good data with a "Data from N days ago" banner. GitHub emails on failure. |
| One company's data missing or malformed | That company is skipped or badged "limited data"; the run continues. |
| EDGAR 403/429 | Exponential backoff from 10 s; resume. |
| Finnhub budget exhausted | Use previous night's price, marked "price from yesterday." |
| No 13F mapping for a ticker | Smart money uses insiders only; section says "Fund data unavailable." |
| Phone offline | Cached data works; watchlist scoring waits for a connection. |
| No Apple Intelligence | Template summaries, no error shown. |
| No Finnhub key on phone | Watchlist report shows everything except price, P/E, PEG and scenarios, with a prompt to add a key. |
| Higher schema major version | "Update the app to see new data." |

## 9. Testing

- **StockCore scoring:** unit tests with hand-built inputs for every part, renormalization, eligibility and tie-breaks.
- **Upside calculator:** tests for growth cap, taper, negative EPS.
- **Parsing:** recorded real responses (EDGAR companyfacts, Form 4 XML, a 13F sample, Finnhub) stored as fixtures. Includes revenue-tag fallbacks, a bank and a REIT. Tests never hit the network.
- **Pipeline:** golden-file test over ~10 fixture companies, comparing output JSON to a checked-in expected copy.
- **AI summary:** number-check tests (accepts matching text, rejects an invented number, falls back).
- **App:** SwiftUI previews with sample data for every state (loading, stale, limited data, offline, no key); UI tests for Top 10 → report and add-to-watchlist.

## 10. Risks

| Risk | Mitigation |
|---|---|
| CUSIP → ticker mapping errors | Name matching plus a manual overrides file in the repo; unmapped tickers degrade gracefully |
| XBRL tag inconsistency across companies | Fallback tag lists; "limited data" badge |
| Finnhub free terms change | `PriceSource` protocol makes swapping providers a one-file change |
| Users read scores as advice | Clear scenario language, assumptions shown, disclaimer on every report |

## 11. Future (not in v1)
- Adjustable scoring weights (sliders)
- Licensed data provider with analyst targets, for the App Store
- Widgets and notifications when a watchlist stock enters the top 10
- Sharing with a small group via TestFlight
