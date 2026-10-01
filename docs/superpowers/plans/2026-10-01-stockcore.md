# StockCore Implementation Plan (Plan 1 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `StockCore`, the UI-free Swift package that fetches SEC EDGAR and Finnhub data, computes growth metrics, scores stocks, and estimates upside, shared by the nightly pipeline and the iOS app.

**Architecture:** A single SwiftPM library with four layers: plain `Codable` models; pure calculators (`MetricCalculator`, `PercentileTable`, `ScoringEngine`, `UpsideCalculator`) with no I/O; parsers for EDGAR JSON and Form 4 XML; and protocol-based data sources over an injectable `HTTPTransport`. `StockAnalyzer` ties the sources together. Every network call goes through a fake transport in tests, so the suite never touches the network.

**Tech Stack:** Swift 6 (language mode 6), SwiftPM, Swift Testing (`import Testing`), Foundation only (`FoundationNetworking` and `FoundationXML` on Linux). No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-10-01-stock-picker-design.md`

**Plan series:** 1 = StockCore (this plan). 2 = Pipeline (nightly job, 13F, publishing). 3 = StockApp (SwiftUI). Plans 2 and 3 are written after this one is built, against the real `StockCore` API.

**Where to run:** All `swift` commands run from the `StockCore/` directory on a Mac with Xcode 16.3+ (Swift 6.1). Git commands run from the repo root.

## Global Constraints

- `swift-tools-version: 6.0`; Swift 6 language mode; package platforms `.iOS(.v17)`, `.macOS(.v14)`; must also build and test on Linux (GitHub Actions `swift:6.1` container).
- No Apple-only frameworks in `StockCore`. On Linux, import `FoundationNetworking` (URLSession) and `FoundationXML` (XMLParser) behind `#if canImport(...)`.
- No third-party dependencies.
- Tests never hit the network; all HTTP goes through `StubTransport`.
- EDGAR: every request sends a `User-Agent` header; capped at **8 requests/second** (SEC max is 10).
- Finnhub: paced at **55 calls/minute** (free tier is 60/min); the API token must never appear in error messages.
- Dates are `"yyyy-MM-dd"` strings in UTC everywhere (comparable as strings).
- Score weights: Growth **40%**, Smart money **30%**, Quality **20%**, Valuation **10%**; missing parts are dropped and the rest renormalized.
- Insider bonus: **+10** percentile points (capped at 100) when **≥3** distinct insiders bought on the open market.
- Insider window: **182 days**. Count only code `P` (buys) and `S` (sells); sells under a 10b5-1 plan are excluded.
- Top 10 eligibility: data for **≥3 of 4** parts; excluded if latest net income **and** free cash flow are both negative; SIC **6000–6799** (banks, insurers, REITs) is "limited data" and excluded.
- Upside: EPS growth capped at **25%**, tapering by **20%** per year, over **3** years.
- Revenue XBRL tag priority: `RevenueFromContractWithCustomerExcludingAssessedTax`, `Revenues`, `SalesRevenueNet`, `RevenueFromContractWithCustomerIncludingAssessedTax`. For each fiscal period the highest-priority tag that has it wins (tags are merged per period, so a company that switched tags keeps its full history).
- Annual facts: form starts with `10-K`, duration **350–380 days**; for the same period end, the most recently **filed** value wins.

## Review Focus

1. **Class-share tickers** (`BRK.B`, `BRK-B`, `brk.b`): directory lookup, Finnhub symbol (`BRK.B`) and holdings file path (`BRK-B.json`) must all resolve the same company. Tests: Task 7 (`lookupNormalizesClassShareTickers`), Task 10 (`classShareTickerUsesDotSymbol`, `holdingsPathUsesNormalizedTicker`).
2. **A 10-K that also reports a three-month Q4 figure with the same period end as the annual figure** must not overwrite the annual value. Test: Task 8 (`ignoresQuarterlyFactsInsideAnnualFilings`).
3. **Restated figures (10-K/A)** must replace the original. Test: Task 8 (`latestFiledValueWinsForRestatements`).
4. **Finnhub returns a zero quote (`c: 0, t: 0`) for unknown or delisted tickers** instead of an error; this must not become a $0 price. Test: Task 10 (`zeroQuoteIsTreatedAsMissing`).
5. **Young or loss-making companies** (fewer than 4 annual reports, negative starting EPS or revenue, zero or negative free cash flow) must yield missing metrics, never NaN or infinity. Tests: Task 2 (`youngCompanyHasNoGrowthMetrics`, `nonPositiveFCFHasNoDebtRatio`, `allMetricValuesAreFinite`).

---

## File Structure

```
StockCore/
├── Package.swift
├── Sources/StockCore/
│   ├── Models/
│   │   ├── Company.swift                 Company + isFinancial
│   │   ├── AnnualFinancials.swift        one fiscal year of figures + freeCashFlow
│   │   ├── PriceQuote.swift
│   │   ├── InsiderTransaction.swift
│   │   ├── InstitutionalQuarter.swift
│   │   ├── CompanyInputs.swift           everything known about one company
│   │   └── ISODay.swift                  "yyyy-MM-dd" helpers
│   ├── Scoring/
│   │   ├── MetricID.swift                MetricID + ScorePart (weights, direction)
│   │   ├── CompanyMetrics.swift
│   │   ├── MetricCalculator.swift        inputs → metrics
│   │   ├── PercentileTable.swift         population → cut points → percentile
│   │   ├── ScoreBreakdown.swift
│   │   ├── ScoringEngine.swift           metrics + table → score
│   │   ├── ReasonWriter.swift            one-line "why it ranked"
│   │   ├── TopPicker.swift               ranked top 10
│   │   └── UpsideCalculator.swift        3-year scenarios
│   ├── Networking/
│   │   ├── StockCoreError.swift
│   │   ├── HTTPTransport.swift           protocol + URLSession implementation
│   │   ├── RateLimiter.swift             actor
│   │   └── EDGARClient.swift             User-Agent, rate limit, retry/backoff
│   ├── EDGAR/
│   │   ├── EDGARURL.swift
│   │   ├── CompanyDirectory.swift        ticker ↔ CIK, search
│   │   ├── EDGARSubmissions.swift        SIC + recent filings
│   │   ├── CompanyFactsParser.swift      XBRL companyfacts → [AnnualFinancials]
│   │   ├── MiniXML.swift                 tiny XML tree on XMLParser
│   │   └── Form4Parser.swift             Form 4 XML → [InsiderTransaction]
│   ├── DataSources/
│   │   ├── InsiderSource.swift           protocol + EDGARInsiderSource
│   │   ├── FundamentalsSource.swift      protocol + EDGARFundamentalsSource
│   │   ├── PriceSource.swift             protocol + FinnhubPriceSource
│   │   └── HoldingsSource.swift          protocol + PublishedHoldingsSource
│   ├── StockReport.swift
│   └── StockAnalyzer.swift               gather inputs, build a report
└── Tests/StockCoreTests/
    ├── Support/
    │   ├── Fixture.swift
    │   ├── StubTransport.swift
    │   └── TestHelpers.swift             approx(), year(), identity table
    ├── Fixtures/                         recorded-shape JSON/XML samples
    └── *Tests.swift                      one file per source file under test
```

---

### Task 1: Package scaffold, models, date helpers, Linux CI

**Files:**
- Create: `StockCore/Package.swift`
- Create: `StockCore/Sources/StockCore/Models/Company.swift`
- Create: `StockCore/Sources/StockCore/Models/AnnualFinancials.swift`
- Create: `StockCore/Sources/StockCore/Models/PriceQuote.swift`
- Create: `StockCore/Sources/StockCore/Models/InsiderTransaction.swift`
- Create: `StockCore/Sources/StockCore/Models/InstitutionalQuarter.swift`
- Create: `StockCore/Sources/StockCore/Models/CompanyInputs.swift`
- Create: `StockCore/Sources/StockCore/Models/ISODay.swift`
- Create: `StockCore/Tests/StockCoreTests/Support/Fixture.swift`
- Create: `StockCore/Tests/StockCoreTests/Support/TestHelpers.swift`
- Create: `StockCore/Tests/StockCoreTests/Fixtures/README.md`
- Create: `StockCore/Tests/StockCoreTests/ModelsTests.swift`
- Create: `.gitignore`
- Create: `.github/workflows/stockcore-tests.yml`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `Company(ticker: String, cik: Int, name: String, sicCode: Int? = nil, sector: String? = nil)`, `var isFinancial: Bool`
  - `AnnualFinancials(periodEnd: String, revenue: Double? = nil, netIncome: Double? = nil, operatingIncome: Double? = nil, epsDiluted: Double? = nil, operatingCashFlow: Double? = nil, capitalExpenditure: Double? = nil, longTermDebt: Double? = nil, cash: Double? = nil)`, `var freeCashFlow: Double?`
  - `PriceQuote(price: Double, peTTM: Double?, asOf: String)`
  - `InsiderTransaction(ownerName: String, ownerCik: Int?, isOfficer: Bool, isDirector: Bool, officerTitle: String?, date: String, code: String, shares: Double, pricePerShare: Double?, isPlanned10b51: Bool)`, `var value: Double`
  - `InstitutionalQuarter(period: String, totalShares: Double, holderCount: Int)`
  - `CompanyInputs(company: Company, financials: [AnnualFinancials], quote: PriceQuote?, insiderTransactions: [InsiderTransaction]?, holdings: [InstitutionalQuarter], asOf: String)` (`insiderTransactions == nil` means "couldn't fetch", `[]` means "none")
  - `ISODay.date(_:) -> Date?`, `ISODay.string(_:) -> String`, `ISODay.days(from:to:) -> Int?`, `ISODay.adding(days:to:) -> String?`
  - Test support: `Fixture.data(_ name: String) throws -> Data`, `approx(_:_:tolerance:)`

- [ ] **Step 1: Create the package manifest and git ignore**

`StockCore/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StockCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "StockCore", targets: ["StockCore"]),
    ],
    targets: [
        .target(name: "StockCore"),
        .testTarget(
            name: "StockCoreTests",
            dependencies: ["StockCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
```

`.gitignore` (repo root):

```
.DS_Store
.build/
.swiftpm/
*.xcuserstate
xcuserdata/
DerivedData/
```

`StockCore/Tests/StockCoreTests/Fixtures/README.md`:

```markdown
Test fixtures. Shapes match real SEC EDGAR and Finnhub responses; values are made up.
```

- [ ] **Step 2: Write test support files**

`StockCore/Tests/StockCoreTests/Support/Fixture.swift`:

```swift
import Foundation

enum FixtureError: Error { case missing(String) }

enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }
}
```

`StockCore/Tests/StockCoreTests/Support/TestHelpers.swift`:

```swift
import Foundation
@testable import StockCore

func approx(_ actual: Double?, _ expected: Double, tolerance: Double = 1e-6) -> Bool {
    guard let actual else { return false }
    return abs(actual - expected) <= tolerance
}
```

- [ ] **Step 3: Write the failing model tests**

`StockCore/Tests/StockCoreTests/ModelsTests.swift`:

```swift
import Foundation
import Testing
@testable import StockCore

@Suite struct ModelsTests {
    @Test func financialSICRangeIsFinancial() {
        #expect(Company(ticker: "JPM", cik: 19617, name: "JPMorgan", sicCode: 6021).isFinancial)
        #expect(Company(ticker: "O", cik: 726728, name: "Realty Income", sicCode: 6798).isFinancial)
        #expect(!Company(ticker: "AAPL", cik: 320193, name: "Apple", sicCode: 3571).isFinancial)
        #expect(!Company(ticker: "X", cik: 1, name: "No SIC").isFinancial)
    }

    @Test func freeCashFlowSubtractsCapex() {
        #expect(AnnualFinancials(periodEnd: "2024-12-31", operatingCashFlow: 30, capitalExpenditure: 8).freeCashFlow == 22)
        #expect(AnnualFinancials(periodEnd: "2024-12-31", operatingCashFlow: 30).freeCashFlow == 30)
        #expect(AnnualFinancials(periodEnd: "2024-12-31", capitalExpenditure: 8).freeCashFlow == nil)
    }

    @Test func insiderValueIsSharesTimesPrice() {
        let tx = InsiderTransaction(ownerName: "A", ownerCik: nil, isOfficer: false, isDirector: true,
                                    officerTitle: nil, date: "2026-08-12", code: "P",
                                    shares: 1000, pricePerShare: 50.25, isPlanned10b51: false)
        #expect(tx.value == 50_250)
        var noPrice = tx
        noPrice.pricePerShare = nil
        #expect(noPrice.value == 0)
    }

    @Test func companyInputsRoundTripsThroughJSON() throws {
        let inputs = CompanyInputs(
            company: Company(ticker: "NOVA", cik: 123456, name: "Novatek", sicCode: 3674, sector: "Semiconductors"),
            financials: [AnnualFinancials(periodEnd: "2024-12-31", revenue: 190)],
            quote: PriceQuote(price: 142.3, peTTM: 38, asOf: "2026-09-30"),
            insiderTransactions: nil,
            holdings: [InstitutionalQuarter(period: "2026-06-30", totalShares: 1_000, holderCount: 40)],
            asOf: "2026-09-30")
        let data = try JSONEncoder().encode(inputs)
        #expect(try JSONDecoder().decode(CompanyInputs.self, from: data) == inputs)
    }

    @Test func isoDayParsesFormatsAndDoesArithmetic() {
        #expect(ISODay.date("2024-12-31") != nil)
        #expect(ISODay.date("not a date") == nil)
        #expect(ISODay.days(from: "2024-01-01", to: "2024-12-31") == 365)
        #expect(ISODay.days(from: "2023-01-01", to: "2023-12-31") == 364)
        #expect(ISODay.adding(days: -182, to: "2026-09-30") == "2026-04-01")
        #expect(ISODay.adding(days: 1, to: "2024-02-28") == "2024-02-29")
    }
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `cd StockCore && swift test --filter ModelsTests`
Expected: build FAILS with errors like `cannot find 'Company' in scope`.

- [ ] **Step 5: Implement the models**

`StockCore/Sources/StockCore/Models/Company.swift`:

```swift
public struct Company: Codable, Hashable, Sendable {
    public var ticker: String
    public var cik: Int
    public var name: String
    public var sicCode: Int?
    public var sector: String?

    public init(ticker: String, cik: Int, name: String, sicCode: Int? = nil, sector: String? = nil) {
        self.ticker = ticker
        self.cik = cik
        self.name = name
        self.sicCode = sicCode
        self.sector = sector
    }

    /// SIC 6000–6799 covers banks, insurers, REITs and other financials, whose
    /// statements don't fit the revenue/margin model.
    public var isFinancial: Bool {
        guard let sicCode else { return false }
        return (6000...6799).contains(sicCode)
    }
}
```

`StockCore/Sources/StockCore/Models/AnnualFinancials.swift`:

```swift
/// One fiscal year of figures from a 10-K. Money values are in USD; EPS is USD per share.
public struct AnnualFinancials: Codable, Hashable, Sendable {
    public var periodEnd: String
    public var revenue: Double?
    public var netIncome: Double?
    public var operatingIncome: Double?
    public var epsDiluted: Double?
    public var operatingCashFlow: Double?
    /// Positive number: cash paid for property, plant and equipment.
    public var capitalExpenditure: Double?
    public var longTermDebt: Double?
    public var cash: Double?

    public init(periodEnd: String, revenue: Double? = nil, netIncome: Double? = nil,
                operatingIncome: Double? = nil, epsDiluted: Double? = nil,
                operatingCashFlow: Double? = nil, capitalExpenditure: Double? = nil,
                longTermDebt: Double? = nil, cash: Double? = nil) {
        self.periodEnd = periodEnd
        self.revenue = revenue
        self.netIncome = netIncome
        self.operatingIncome = operatingIncome
        self.epsDiluted = epsDiluted
        self.operatingCashFlow = operatingCashFlow
        self.capitalExpenditure = capitalExpenditure
        self.longTermDebt = longTermDebt
        self.cash = cash
    }

    public var freeCashFlow: Double? {
        guard let operatingCashFlow else { return nil }
        return operatingCashFlow - (capitalExpenditure ?? 0)
    }
}
```

`StockCore/Sources/StockCore/Models/PriceQuote.swift`:

```swift
public struct PriceQuote: Codable, Hashable, Sendable {
    public var price: Double
    /// Trailing-twelve-month P/E. Nil or ≤ 0 when earnings are negative or unknown.
    public var peTTM: Double?
    public var asOf: String

    public init(price: Double, peTTM: Double?, asOf: String) {
        self.price = price
        self.peTTM = peTTM
        self.asOf = asOf
    }
}
```

`StockCore/Sources/StockCore/Models/InsiderTransaction.swift`:

```swift
/// One row of a Form 4 non-derivative table.
public struct InsiderTransaction: Codable, Hashable, Sendable {
    public var ownerName: String
    public var ownerCik: Int?
    public var isOfficer: Bool
    public var isDirector: Bool
    public var officerTitle: String?
    public var date: String
    /// SEC transaction code: "P" open-market buy, "S" open-market sale, others ignored by scoring.
    public var code: String
    public var shares: Double
    public var pricePerShare: Double?
    public var isPlanned10b51: Bool

    public init(ownerName: String, ownerCik: Int?, isOfficer: Bool, isDirector: Bool,
                officerTitle: String?, date: String, code: String, shares: Double,
                pricePerShare: Double?, isPlanned10b51: Bool) {
        self.ownerName = ownerName
        self.ownerCik = ownerCik
        self.isOfficer = isOfficer
        self.isDirector = isDirector
        self.officerTitle = officerTitle
        self.date = date
        self.code = code
        self.shares = shares
        self.pricePerShare = pricePerShare
        self.isPlanned10b51 = isPlanned10b51
    }

    public var value: Double { shares * (pricePerShare ?? 0) }
}
```

`StockCore/Sources/StockCore/Models/InstitutionalQuarter.swift`:

```swift
/// 13F aggregate for one ticker at one quarter end.
public struct InstitutionalQuarter: Codable, Hashable, Sendable {
    public var period: String
    public var totalShares: Double
    public var holderCount: Int

    public init(period: String, totalShares: Double, holderCount: Int) {
        self.period = period
        self.totalShares = totalShares
        self.holderCount = holderCount
    }
}
```

`StockCore/Sources/StockCore/Models/CompanyInputs.swift`:

```swift
/// Everything gathered about one company before scoring.
public struct CompanyInputs: Codable, Hashable, Sendable {
    public var company: Company
    /// Sorted oldest → newest.
    public var financials: [AnnualFinancials]
    public var quote: PriceQuote?
    /// nil = insider data couldn't be fetched; [] = fetched, no transactions.
    public var insiderTransactions: [InsiderTransaction]?
    /// Sorted oldest → newest.
    public var holdings: [InstitutionalQuarter]
    public var asOf: String

    public init(company: Company, financials: [AnnualFinancials], quote: PriceQuote?,
                insiderTransactions: [InsiderTransaction]?, holdings: [InstitutionalQuarter],
                asOf: String) {
        self.company = company
        self.financials = financials.sorted { $0.periodEnd < $1.periodEnd }
        self.quote = quote
        self.insiderTransactions = insiderTransactions
        self.holdings = holdings.sorted { $0.period < $1.period }
        self.asOf = asOf
    }
}
```

`StockCore/Sources/StockCore/Models/ISODay.swift`:

```swift
import Foundation

/// Helpers for "yyyy-MM-dd" day strings in UTC.
public enum ISODay {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    public static func date(_ string: String) -> Date? {
        let parts = string.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    public static func string(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(pad(c.year ?? 0, 4))-\(pad(c.month ?? 0, 2))-\(pad(c.day ?? 0, 2))"
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    public static func days(from start: String, to end: String) -> Int? {
        guard let a = date(start), let b = date(end) else { return nil }
        return Int((b.timeIntervalSince(a) / 86_400).rounded())
    }

    public static func adding(days: Int, to day: String) -> String? {
        guard let d = date(day) else { return nil }
        return string(d.addingTimeInterval(Double(days) * 86_400))
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd StockCore && swift test --filter ModelsTests`
Expected: PASS, 5 tests.

- [ ] **Step 7: Add the Linux CI workflow**

`.github/workflows/stockcore-tests.yml`:

```yaml
name: StockCore tests

on:
  push:
    paths: ["StockCore/**", ".github/workflows/stockcore-tests.yml"]
  pull_request:
    paths: ["StockCore/**"]

jobs:
  linux:
    runs-on: ubuntu-latest
    container: swift:6.1
    steps:
      - uses: actions/checkout@v4
      - name: Test
        working-directory: StockCore
        run: swift test
```

Linux-only keeps CI at $0 on private repos; macOS is covered by local runs.

- [ ] **Step 8: Commit**

```bash
git add .gitignore .github/workflows/stockcore-tests.yml StockCore
git commit -m "feat(core): scaffold StockCore package with models and Linux CI"
```

---

### Task 2: Metric IDs and MetricCalculator

**Files:**
- Create: `StockCore/Sources/StockCore/Scoring/MetricID.swift`
- Create: `StockCore/Sources/StockCore/Scoring/CompanyMetrics.swift`
- Create: `StockCore/Sources/StockCore/Scoring/MetricCalculator.swift`
- Modify: `StockCore/Tests/StockCoreTests/Support/TestHelpers.swift` (append helpers)
- Test: `StockCore/Tests/StockCoreTests/MetricCalculatorTests.swift`

**Interfaces:**
- Consumes: `CompanyInputs`, `AnnualFinancials`, `InsiderTransaction`, `InstitutionalQuarter`, `ISODay` (Task 1).
- Produces:
  - `enum ScorePart: String, CaseIterable` with cases `growth, smartMoney, quality, valuation`; `var weight: Double`
  - `enum MetricID: String, CaseIterable` with cases `revenueCAGR3Y, epsCAGR3Y, growthAcceleration, insiderNetBuying, institutionalShareChange, holderCountChange, operatingMarginTrend, freeCashFlowMargin, netDebtToFCF, peg`; `var part: ScorePart`; `var higherIsBetter: Bool`
  - `struct CompanyMetrics` with `values: [MetricID: Double]`, `strictEPSCAGR3Y: Double?`, `distinctInsiderBuyers: Int`, `latestNetIncome: Double?`, `latestFreeCashFlow: Double?`, `subscript(_ id: MetricID) -> Double?`
  - `MetricCalculator.metrics(for: CompanyInputs) -> CompanyMetrics`, `MetricCalculator.insiderWindowDays == 182`

- [ ] **Step 1: Add test helpers**

Append to `StockCore/Tests/StockCoreTests/Support/TestHelpers.swift`:

```swift
func year(_ end: String, revenue: Double? = nil, eps: Double? = nil, opIncome: Double? = nil,
          netIncome: Double? = nil, ocf: Double? = nil, capex: Double? = nil,
          debt: Double? = nil, cash: Double? = nil) -> AnnualFinancials {
    AnnualFinancials(periodEnd: end, revenue: revenue, netIncome: netIncome, operatingIncome: opIncome,
                     epsDiluted: eps, operatingCashFlow: ocf, capitalExpenditure: capex,
                     longTermDebt: debt, cash: cash)
}

func insider(_ name: String, _ code: String, _ date: String, shares: Double, price: Double,
             planned: Bool = false) -> InsiderTransaction {
    InsiderTransaction(ownerName: name, ownerCik: nil, isOfficer: true, isDirector: false,
                       officerTitle: nil, date: date, code: code, shares: shares,
                       pricePerShare: price, isPlanned10b51: planned)
}

let testCompany = Company(ticker: "NOVA", cik: 123456, name: "Novatek", sicCode: 3674)

func inputs(financials: [AnnualFinancials] = [], quote: PriceQuote? = nil,
            insiders: [InsiderTransaction]? = [], holdings: [InstitutionalQuarter] = [],
            company: Company = testCompany, asOf: String = "2026-09-30") -> CompanyInputs {
    CompanyInputs(company: company, financials: financials, quote: quote,
                  insiderTransactions: insiders, holdings: holdings, asOf: asOf)
}
```

- [ ] **Step 2: Write the failing tests**

`StockCore/Tests/StockCoreTests/MetricCalculatorTests.swift`:

```swift
import Foundation
import Testing
@testable import StockCore

@Suite struct MetricCalculatorTests {
    let fourYears = [
        year("2021-12-31", revenue: 100, eps: 1.0, opIncome: 10),
        year("2022-12-31", revenue: 100, eps: 1.1, opIncome: 11),
        year("2023-12-31", revenue: 100, eps: 1.2, opIncome: 12),
        year("2024-12-31", revenue: 133.1, eps: 1.331, opIncome: 26.62, netIncome: 20,
             ocf: 30, capex: 8, debt: 50, cash: 6),
    ]

    @Test func growthMetrics() {
        let m = MetricCalculator.metrics(for: inputs(financials: fourYears))
        #expect(approx(m[.revenueCAGR3Y], 0.10))
        #expect(approx(m[.growthAcceleration], 0.331 - 0.10))
        #expect(approx(m[.epsCAGR3Y], 0.10))
        #expect(approx(m.strictEPSCAGR3Y, 0.10))
    }

    @Test func qualityMetrics() {
        let m = MetricCalculator.metrics(for: inputs(financials: fourYears))
        #expect(approx(m[.operatingMarginTrend], 0.20 - 0.10))
        #expect(approx(m[.freeCashFlowMargin], 22 / 133.1))
        #expect(approx(m[.netDebtToFCF], (50 - 6) / 22.0))
        #expect(m.latestNetIncome == 20)
        #expect(m.latestFreeCashFlow == 22)
    }

    @Test func pegUsesStrictEPSGrowth() {
        let m = MetricCalculator.metrics(for: inputs(
            financials: fourYears, quote: PriceQuote(price: 40, peTTM: 30, asOf: "2026-09-30")))
        #expect(approx(m[.peg], 30 / 10.0))
    }

    @Test func negativeStartingEPSFallsBackToOperatingIncome() {
        var years = fourYears
        years[0].epsDiluted = -1
        let m = MetricCalculator.metrics(for: inputs(
            financials: years, quote: PriceQuote(price: 40, peTTM: 30, asOf: "2026-09-30")))
        #expect(m.strictEPSCAGR3Y == nil)
        #expect(approx(m[.epsCAGR3Y], pow(26.62 / 10, 1.0 / 3) - 1))
        #expect(m[.peg] == nil)
    }

    @Test func youngCompanyHasNoGrowthMetrics() {
        let m = MetricCalculator.metrics(for: inputs(financials: Array(fourYears.suffix(3))))
        #expect(m[.revenueCAGR3Y] == nil)
        #expect(m[.epsCAGR3Y] == nil)
        #expect(m[.growthAcceleration] == nil)
        #expect(m[.operatingMarginTrend] == nil)
        #expect(m[.freeCashFlowMargin] != nil)
    }

    @Test func nonPositiveFCFHasNoDebtRatio() {
        var years = fourYears
        years[3].capitalExpenditure = 30  // FCF = 0
        let m = MetricCalculator.metrics(for: inputs(financials: years))
        #expect(m[.netDebtToFCF] == nil)
        #expect(m[.freeCashFlowMargin] == 0)
    }

    @Test func allMetricValuesAreFinite() {
        let weird = [
            year("2021-12-31", revenue: 0, eps: 0, opIncome: 0),
            year("2022-12-31", revenue: -5, eps: -1, opIncome: -3),
            year("2023-12-31", revenue: 0, eps: 0, opIncome: 0),
            year("2024-12-31", revenue: 0, eps: -2, opIncome: -1, netIncome: -4, ocf: -1, capex: 2, debt: 10),
        ]
        let m = MetricCalculator.metrics(for: inputs(
            financials: weird, quote: PriceQuote(price: 5, peTTM: -3, asOf: "2026-09-30"),
            holdings: [InstitutionalQuarter(period: "2026-03-31", totalShares: 0, holderCount: 0),
                       InstitutionalQuarter(period: "2026-06-30", totalShares: 10, holderCount: 2)]))
        #expect(m.values.values.allSatisfy(\.isFinite))
    }

    @Test func insiderNetBuyingCountsOnlyRecentOpenMarketTrades() {
        let txs = [
            insider("A", "P", "2026-08-01", shares: 100, price: 10),
            insider("B", "P", "2026-07-01", shares: 50, price: 10),
            insider("A", "P", "2026-07-15", shares: 10, price: 10),
            insider("C", "S", "2026-08-02", shares: 30, price: 10, planned: true),
            insider("D", "S", "2026-09-01", shares: 20, price: 10),
            insider("E", "M", "2026-09-01", shares: 999, price: 10),
            insider("F", "P", "2025-12-01", shares: 1000, price: 10),
        ]
        let m = MetricCalculator.metrics(for: inputs(insiders: txs))
        #expect(m[.insiderNetBuying] == 1000 + 500 + 100 - 200)
        #expect(m.distinctInsiderBuyers == 2)
    }

    @Test func missingInsiderDataLeavesMetricOut() {
        let m = MetricCalculator.metrics(for: inputs(insiders: nil))
        #expect(m[.insiderNetBuying] == nil)
        #expect(m.distinctInsiderBuyers == 0)
    }

    @Test func noInsiderTradesIsZeroNotMissing() {
        #expect(MetricCalculator.metrics(for: inputs(insiders: []))[.insiderNetBuying] == 0)
    }

    @Test func institutionalChangesUseLastTwoQuarters() {
        let q = [
            InstitutionalQuarter(period: "2026-06-30", totalShares: 1100, holderCount: 50),
            InstitutionalQuarter(period: "2025-12-31", totalShares: 500, holderCount: 10),
            InstitutionalQuarter(period: "2026-03-31", totalShares: 1000, holderCount: 40),
        ]
        let m = MetricCalculator.metrics(for: inputs(holdings: q))
        #expect(approx(m[.institutionalShareChange], 0.10))
        #expect(approx(m[.holderCountChange], 0.25))
    }

    @Test func metricsEncodeWithReadableKeys() throws {
        let m = MetricCalculator.metrics(for: inputs(financials: fourYears))
        let json = String(decoding: try JSONEncoder().encode(m), as: UTF8.self)
        #expect(json.contains("\"revenueCAGR3Y\""))
        #expect(try JSONDecoder().decode(CompanyMetrics.self, from: Data(json.utf8)) == m)
    }

    @Test func partsAndDirections() {
        #expect(approx(ScorePart.allCases.map(\.weight).reduce(0, +), 1.0))
        #expect(MetricID.peg.part == .valuation && !MetricID.peg.higherIsBetter)
        #expect(MetricID.netDebtToFCF.part == .quality && !MetricID.netDebtToFCF.higherIsBetter)
        #expect(MetricID.allCases.filter { $0.part == .growth }.count == 3)
        #expect(MetricID.allCases.filter { $0.part == .smartMoney }.count == 3)
        #expect(MetricID.allCases.filter { $0.part == .quality }.count == 3)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd StockCore && swift test --filter MetricCalculatorTests`
Expected: build FAILS with `cannot find 'MetricCalculator' in scope`.

- [ ] **Step 4: Implement MetricID and CompanyMetrics**

`StockCore/Sources/StockCore/Scoring/MetricID.swift`:

```swift
public enum ScorePart: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
    case growth, smartMoney, quality, valuation

    public var weight: Double {
        switch self {
        case .growth: 0.40
        case .smartMoney: 0.30
        case .quality: 0.20
        case .valuation: 0.10
        }
    }
}

public enum MetricID: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
    case revenueCAGR3Y, epsCAGR3Y, growthAcceleration
    case insiderNetBuying, institutionalShareChange, holderCountChange
    case operatingMarginTrend, freeCashFlowMargin, netDebtToFCF
    case peg

    public var part: ScorePart {
        switch self {
        case .revenueCAGR3Y, .epsCAGR3Y, .growthAcceleration: .growth
        case .insiderNetBuying, .institutionalShareChange, .holderCountChange: .smartMoney
        case .operatingMarginTrend, .freeCashFlowMargin, .netDebtToFCF: .quality
        case .peg: .valuation
        }
    }

    public var higherIsBetter: Bool {
        switch self {
        case .netDebtToFCF, .peg: false
        default: true
        }
    }
}
```

`StockCore/Sources/StockCore/Scoring/CompanyMetrics.swift`:

```swift
public struct CompanyMetrics: Codable, Hashable, Sendable {
    /// Only metrics that could be computed are present.
    public var values: [MetricID: Double]
    /// True diluted-EPS CAGR (no operating-income fallback). Used for PEG and upside.
    public var strictEPSCAGR3Y: Double?
    public var distinctInsiderBuyers: Int
    public var latestNetIncome: Double?
    public var latestFreeCashFlow: Double?

    public init(values: [MetricID: Double] = [:], strictEPSCAGR3Y: Double? = nil,
                distinctInsiderBuyers: Int = 0, latestNetIncome: Double? = nil,
                latestFreeCashFlow: Double? = nil) {
        self.values = values
        self.strictEPSCAGR3Y = strictEPSCAGR3Y
        self.distinctInsiderBuyers = distinctInsiderBuyers
        self.latestNetIncome = latestNetIncome
        self.latestFreeCashFlow = latestFreeCashFlow
    }

    public subscript(_ id: MetricID) -> Double? { values[id] }
}
```

- [ ] **Step 5: Implement MetricCalculator**

`StockCore/Sources/StockCore/Scoring/MetricCalculator.swift`:

```swift
import Foundation

public enum MetricCalculator {
    public static let insiderWindowDays = 182

    public static func metrics(for inputs: CompanyInputs) -> CompanyMetrics {
        var m = CompanyMetrics()
        addFinancialMetrics(inputs.financials, into: &m)
        addValuation(inputs.quote, into: &m)
        addInsiderMetrics(inputs.insiderTransactions, asOf: inputs.asOf, into: &m)
        addHoldingsMetrics(inputs.holdings, into: &m)
        m.values = m.values.filter { $0.value.isFinite }
        return m
    }

    private static func addFinancialMetrics(_ financials: [AnnualFinancials], into m: inout CompanyMetrics) {
        let years = financials.sorted { $0.periodEnd < $1.periodEnd }
        guard let last = years.last else { return }
        m.latestNetIncome = last.netIncome
        m.latestFreeCashFlow = last.freeCashFlow

        if let fcf = last.freeCashFlow, let revenue = last.revenue, revenue > 0 {
            m.values[.freeCashFlowMargin] = fcf / revenue
        }
        if let fcf = last.freeCashFlow, fcf > 0, last.longTermDebt != nil || last.cash != nil {
            m.values[.netDebtToFCF] = ((last.longTermDebt ?? 0) - (last.cash ?? 0)) / fcf
        }

        guard years.count >= 4 else { return }
        let first = years[years.count - 4]
        let previous = years[years.count - 2]

        if let revenueCAGR = cagr(first.revenue, last.revenue) {
            m.values[.revenueCAGR3Y] = revenueCAGR
            if let p = previous.revenue, let l = last.revenue, p > 0 {
                m.values[.growthAcceleration] = (l / p - 1) - revenueCAGR
            }
        }
        m.strictEPSCAGR3Y = cagr(first.epsDiluted, last.epsDiluted)
        m.values[.epsCAGR3Y] = m.strictEPSCAGR3Y ?? cagr(first.operatingIncome, last.operatingIncome)
        if let start = operatingMargin(first), let end = operatingMargin(last) {
            m.values[.operatingMarginTrend] = end - start
        }
    }

    private static func addValuation(_ quote: PriceQuote?, into m: inout CompanyMetrics) {
        guard let pe = quote?.peTTM, pe > 0, let growth = m.strictEPSCAGR3Y, growth > 0 else { return }
        m.values[.peg] = pe / (growth * 100)
    }

    private static func addInsiderMetrics(_ transactions: [InsiderTransaction]?, asOf: String,
                                          into m: inout CompanyMetrics) {
        guard let transactions, let since = ISODay.adding(days: -insiderWindowDays, to: asOf) else { return }
        let recent = transactions.filter { $0.date >= since && $0.date <= asOf }
        let buys = recent.filter { $0.code == "P" }
        let sells = recent.filter { $0.code == "S" && !$0.isPlanned10b51 }
        m.values[.insiderNetBuying] = buys.reduce(0) { $0 + $1.value } - sells.reduce(0) { $0 + $1.value }
        m.distinctInsiderBuyers = Set(buys.map(\.ownerName)).count
    }

    private static func addHoldingsMetrics(_ holdings: [InstitutionalQuarter], into m: inout CompanyMetrics) {
        let quarters = holdings.sorted { $0.period < $1.period }
        guard quarters.count >= 2 else { return }
        let previous = quarters[quarters.count - 2]
        let latest = quarters[quarters.count - 1]
        if previous.totalShares > 0 {
            m.values[.institutionalShareChange] = latest.totalShares / previous.totalShares - 1
        }
        if previous.holderCount > 0 {
            m.values[.holderCountChange] = Double(latest.holderCount) / Double(previous.holderCount) - 1
        }
    }

    static func cagr(_ start: Double?, _ end: Double?, years: Double = 3) -> Double? {
        guard let start, let end, start > 0, end > 0 else { return nil }
        return pow(end / start, 1 / years) - 1
    }

    static func operatingMargin(_ year: AnnualFinancials) -> Double? {
        guard let operating = year.operatingIncome, let revenue = year.revenue, revenue > 0 else { return nil }
        return operating / revenue
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd StockCore && swift test --filter MetricCalculatorTests`
Expected: PASS, 13 tests.

- [ ] **Step 7: Commit**

```bash
git add StockCore
git commit -m "feat(core): compute growth, quality, valuation and smart-money metrics"
```

---

### Task 3: PercentileTable

**Files:**
- Create: `StockCore/Sources/StockCore/Scoring/PercentileTable.swift`
- Modify: `StockCore/Tests/StockCoreTests/Support/TestHelpers.swift` (append identity table)
- Test: `StockCore/Tests/StockCoreTests/PercentileTableTests.swift`

**Interfaces:**
- Consumes: `MetricID`, `CompanyMetrics` (Task 2).
- Produces:
  - `PercentileTable(cutPoints: [MetricID: [Double]])` (101 ascending cut points per metric)
  - `static func build(from population: [CompanyMetrics]) -> PercentileTable`
  - `func percentile(of value: Double, for id: MetricID) -> Double?` (raw 0…100, higher value → higher percentile; ties get the midpoint; nil if the metric has no cut points)
  - Test helper `PercentileTable.identity` where `percentile(of: v) == v` for 0…100

- [ ] **Step 1: Add the identity table helper**

Append to `StockCore/Tests/StockCoreTests/Support/TestHelpers.swift`:

```swift
extension PercentileTable {
    /// percentile(of: v) == v for v in 0...100, for every metric.
    static let identity = PercentileTable(cutPoints: Dictionary(
        uniqueKeysWithValues: MetricID.allCases.map { ($0, (0...100).map(Double.init)) }))
}
```

- [ ] **Step 2: Write the failing tests**

`StockCore/Tests/StockCoreTests/PercentileTableTests.swift`:

```swift
import Foundation
import Testing
@testable import StockCore

@Suite struct PercentileTableTests {
    func population(_ values: [Double], _ id: MetricID = .revenueCAGR3Y) -> [CompanyMetrics] {
        values.map { CompanyMetrics(values: [id: $0]) }
    }

    @Test func buildsOneHundredOneCutPoints() {
        let table = PercentileTable.build(from: population((0...100).map(Double.init)))
        #expect(table.cutPoints[.revenueCAGR3Y] == (0...100).map(Double.init))
        #expect(table.cutPoints[.peg] == nil)
    }

    @Test func percentileInterpolatesAndClamps() {
        let table = PercentileTable.build(from: population((0...100).map(Double.init)))
        #expect(table.percentile(of: 50, for: .revenueCAGR3Y) == 50)
        #expect(approx(table.percentile(of: 50.5, for: .revenueCAGR3Y), 50.5))
        #expect(table.percentile(of: -5, for: .revenueCAGR3Y) == 0)
        #expect(table.percentile(of: 500, for: .revenueCAGR3Y) == 100)
    }

    @Test func tiesGetTheMidpoint() {
        let table = PercentileTable.build(from: population([0, 0, 0, 0, 10]))
        #expect(table.percentile(of: 0, for: .revenueCAGR3Y) == 37.5)
        #expect(table.percentile(of: 10, for: .revenueCAGR3Y) == 100)
        #expect(approx(table.percentile(of: 5, for: .revenueCAGR3Y), 87.5))
    }

    @Test func singleValuePopulationIsFiftieth() {
        let table = PercentileTable.build(from: population([3]))
        #expect(table.percentile(of: 3, for: .revenueCAGR3Y) == 50)
    }

    @Test func missingMetricOrNonFiniteValueIsNil() {
        let table = PercentileTable.build(from: population([1, 2, 3]))
        #expect(table.percentile(of: 1, for: .peg) == nil)
        #expect(table.percentile(of: .nan, for: .revenueCAGR3Y) == nil)
    }

    @Test func ignoresCompaniesMissingTheMetric() {
        var pop = population([1, 2, 3])
        pop.append(CompanyMetrics(values: [.peg: 2]))
        let table = PercentileTable.build(from: pop)
        #expect(table.cutPoints[.revenueCAGR3Y]?.first == 1)
        #expect(table.cutPoints[.revenueCAGR3Y]?.last == 3)
    }

    @Test func roundTripsThroughJSON() throws {
        let table = PercentileTable.build(from: population([1, 2, 3]))
        let data = try JSONEncoder().encode(table)
        #expect(try JSONDecoder().decode(PercentileTable.self, from: data) == table)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd StockCore && swift test --filter PercentileTableTests`
Expected: build FAILS with `cannot find 'PercentileTable' in scope`.

- [ ] **Step 4: Implement PercentileTable**

`StockCore/Sources/StockCore/Scoring/PercentileTable.swift`:

```swift
/// S&P 500 distribution of each metric, as 101 cut points (0th…100th percentile).
/// Published nightly so the phone can score watchlist stocks on the same scale.
public struct PercentileTable: Codable, Hashable, Sendable {
    public var cutPoints: [MetricID: [Double]]

    public init(cutPoints: [MetricID: [Double]]) {
        self.cutPoints = cutPoints
    }

    public static func build(from population: [CompanyMetrics]) -> PercentileTable {
        var cuts: [MetricID: [Double]] = [:]
        for id in MetricID.allCases {
            let values = population.compactMap { $0[id] }.filter(\.isFinite).sorted()
            guard !values.isEmpty else { continue }
            cuts[id] = (0...100).map { quantile(values, index: $0) }
        }
        return PercentileTable(cutPoints: cuts)
    }

    /// Linear-interpolated quantile at index/100. Integer arithmetic keeps
    /// positions exact (n = 101 gives cut point i == sorted[i]).
    static func quantile(_ sorted: [Double], index: Int) -> Double {
        let numerator = index * (sorted.count - 1)
        let lower = numerator / 100
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = Double(numerator % 100) / 100
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    /// Raw percentile 0…100 (higher value → higher percentile). Ties get the
    /// midpoint of the cut points they span.
    public func percentile(of value: Double, for id: MetricID) -> Double? {
        guard let c = cutPoints[id], c.count == 101, value.isFinite else { return nil }
        if value < c[0] { return 0 }
        if value > c[100] { return 100 }
        if let first = c.firstIndex(of: value), let last = c.lastIndex(of: value) {
            return Double(first + last) / 2
        }
        // c[0] < value < c[100] and value isn't a cut point, so i is in 1...100.
        guard let i = c.firstIndex(where: { $0 > value }) else { return 100 }
        return Double(i - 1) + (value - c[i - 1]) / (c[i] - c[i - 1])
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd StockCore && swift test --filter PercentileTableTests`
Expected: PASS, 7 tests.

- [ ] **Step 6: Commit**

```bash
git add StockCore
git commit -m "feat(core): add percentile table for cross-company ranking"
```

---

### Task 4: ScoringEngine, ReasonWriter, TopPicker

**Files:**
- Create: `StockCore/Sources/StockCore/Scoring/ScoreBreakdown.swift`
- Create: `StockCore/Sources/StockCore/Scoring/ReasonWriter.swift`
- Create: `StockCore/Sources/StockCore/Scoring/ScoringEngine.swift`
- Create: `StockCore/Sources/StockCore/Scoring/TopPicker.swift`
- Test: `StockCore/Tests/StockCoreTests/ScoringEngineTests.swift`
- Test: `StockCore/Tests/StockCoreTests/TopPickerTests.swift`

**Interfaces:**
- Consumes: `Company` (Task 1), `MetricID`, `ScorePart`, `CompanyMetrics` (Task 2), `PercentileTable` (Task 3).
- Produces:
  - `struct ScoreBreakdown` with `total: Int?`, `parts: [ScorePart: Int]`, `metricPercentiles: [MetricID: Double]` (oriented so higher = better, after the insider bonus), `isEligibleForTop10: Bool`, `limitedData: Bool`, `reason: String`; public memberwise init
  - `ScoringEngine().score(company: Company, metrics: CompanyMetrics, table: PercentileTable) -> ScoreBreakdown`
  - `struct RankedPick` with `rank: Int, ticker: String, name: String, score: Int, reason: String`
  - `TopPicker.pick(_ scored: [(company: Company, score: ScoreBreakdown)], count: Int = 10) -> [RankedPick]`

- [ ] **Step 1: Write the failing scoring tests**

`StockCore/Tests/StockCoreTests/ScoringEngineTests.swift`:

```swift
import Testing
@testable import StockCore

@Suite struct ScoringEngineTests {
    let engine = ScoringEngine()

    func metrics(_ value: Double, except overrides: [MetricID: Double] = [:], buyers: Int = 0,
                 netIncome: Double? = 10, fcf: Double? = 10) -> CompanyMetrics {
        var values = Dictionary(uniqueKeysWithValues: MetricID.allCases.map { ($0, value) })
        values.merge(overrides) { _, new in new }
        return CompanyMetrics(values: values, strictEPSCAGR3Y: 0.1, distinctInsiderBuyers: buyers,
                              latestNetIncome: netIncome, latestFreeCashFlow: fcf)
    }

    @Test func weightedTotalWithLowerIsBetterMetricsInverted() {
        let s = engine.score(company: testCompany, metrics: metrics(80), table: .identity)
        #expect(s.parts == [.growth: 80, .smartMoney: 80, .quality: 60, .valuation: 20])
        #expect(s.total == 70)
        #expect(s.metricPercentiles[.peg] == 20)
        #expect(s.isEligibleForTop10)
        #expect(!s.limitedData)
    }

    @Test func missingPartsAreRenormalized() {
        let m = CompanyMetrics(values: [
            .revenueCAGR3Y: 90, .epsCAGR3Y: 90, .growthAcceleration: 90,
            .operatingMarginTrend: 60, .freeCashFlowMargin: 60, .netDebtToFCF: 40,
        ], latestNetIncome: 1, latestFreeCashFlow: 1)
        let s = engine.score(company: testCompany, metrics: m, table: .identity)
        #expect(s.total == 80)
        #expect(s.parts.keys.sorted { $0.rawValue < $1.rawValue } == [.growth, .quality])
        #expect(!s.isEligibleForTop10)
        #expect(s.limitedData)
    }

    @Test func noMetricsMeansNoScore() {
        let s = engine.score(company: testCompany, metrics: CompanyMetrics(), table: .identity)
        #expect(s.total == nil)
        #expect(s.parts.isEmpty)
        #expect(!s.isEligibleForTop10)
        #expect(s.reason == "")
    }

    @Test func threeInsiderBuyersAddBonusCappedAt100() {
        let s = engine.score(company: testCompany,
                             metrics: metrics(80, except: [.insiderNetBuying: 95], buyers: 3),
                             table: .identity)
        #expect(s.metricPercentiles[.insiderNetBuying] == 100)
        let noBonus = engine.score(company: testCompany,
                                   metrics: metrics(80, except: [.insiderNetBuying: 95], buyers: 2),
                                   table: .identity)
        #expect(noBonus.metricPercentiles[.insiderNetBuying] == 95)
    }

    @Test func financialCompaniesAreLimitedAndIneligible() {
        let bank = Company(ticker: "BANK", cik: 1, name: "A Bank", sicCode: 6022)
        let s = engine.score(company: bank, metrics: metrics(80), table: .identity)
        #expect(s.total == 70)
        #expect(!s.isEligibleForTop10)
        #expect(s.limitedData)
    }

    @Test func lossMakingCashBurnersAreIneligible() {
        let s = engine.score(company: testCompany, metrics: metrics(80, netIncome: -1, fcf: -1),
                             table: .identity)
        #expect(!s.isEligibleForTop10)
        #expect(!s.limitedData)
        let onlyLoss = engine.score(company: testCompany, metrics: metrics(80, netIncome: -1, fcf: 5),
                                    table: .identity)
        #expect(onlyLoss.isEligibleForTop10)
    }

    @Test func reasonNamesTheTwoStrongestMetrics() {
        let m = metrics(50, except: [.revenueCAGR3Y: 94, .freeCashFlowMargin: 90])
        let s = engine.score(company: testCompany, metrics: m, table: .identity)
        #expect(s.reason == "Top 6% revenue growth · Top 10% cash generation")
    }

    @Test func insiderReasonCountsBuyers() {
        let m = metrics(50, except: [.insiderNetBuying: 99, .revenueCAGR3Y: 97], buyers: 3)
        let s = engine.score(company: testCompany, metrics: m, table: .identity)
        #expect(s.reason == "3 insiders bought recently · Top 3% revenue growth")
    }
}
```

- [ ] **Step 2: Write the failing TopPicker tests**

`StockCore/Tests/StockCoreTests/TopPickerTests.swift`:

```swift
import Testing
@testable import StockCore

@Suite struct TopPickerTests {
    func entry(_ ticker: String, total: Int?, growth: Int = 50, eligible: Bool = true)
        -> (company: Company, score: ScoreBreakdown) {
        (Company(ticker: ticker, cik: 1, name: "\(ticker) Inc"),
         ScoreBreakdown(total: total, parts: [.growth: growth], metricPercentiles: [:],
                        isEligibleForTop10: eligible, limitedData: !eligible, reason: "r-\(ticker)"))
    }

    @Test func ranksEligibleByScoreThenGrowthThenTicker() {
        let picks = TopPicker.pick([
            entry("LOW", total: 60),
            entry("BANK", total: 99, eligible: false),
            entry("TIEB", total: 80, growth: 70),
            entry("TIEA", total: 80, growth: 90),
            entry("SAME2", total: 70, growth: 50),
            entry("SAME1", total: 70, growth: 50),
            entry("NONE", total: nil),
        ])
        #expect(picks.map(\.ticker) == ["TIEA", "TIEB", "SAME1", "SAME2", "LOW"])
        #expect(picks.map(\.rank) == [1, 2, 3, 4, 5])
        #expect(picks[0].score == 80)
        #expect(picks[0].reason == "r-TIEA")
        #expect(picks[0].name == "TIEA Inc")
    }

    @Test func limitsToCount() {
        let many = (0..<25).map { entry("T\($0)", total: $0) }
        #expect(TopPicker.pick(many).count == 10)
        #expect(TopPicker.pick(many).first?.ticker == "T24")
        #expect(TopPicker.pick(many, count: 3).count == 3)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd StockCore && swift test --filter "ScoringEngineTests|TopPickerTests"`
Expected: build FAILS with `cannot find 'ScoringEngine' in scope`.

- [ ] **Step 4: Implement ScoreBreakdown and ReasonWriter**

`StockCore/Sources/StockCore/Scoring/ScoreBreakdown.swift`:

```swift
public struct ScoreBreakdown: Codable, Hashable, Sendable {
    /// 0…100, nil when no part could be scored.
    public var total: Int?
    public var parts: [ScorePart: Int]
    /// Oriented so higher is always better; includes the insider bonus.
    public var metricPercentiles: [MetricID: Double]
    public var isEligibleForTop10: Bool
    public var limitedData: Bool
    public var reason: String

    public init(total: Int?, parts: [ScorePart: Int], metricPercentiles: [MetricID: Double],
                isEligibleForTop10: Bool, limitedData: Bool, reason: String) {
        self.total = total
        self.parts = parts
        self.metricPercentiles = metricPercentiles
        self.isEligibleForTop10 = isEligibleForTop10
        self.limitedData = limitedData
        self.reason = reason
    }
}
```

`StockCore/Sources/StockCore/Scoring/ReasonWriter.swift`:

```swift
import Foundation

/// Builds the one-line "why it ranked" from the two strongest metrics.
enum ReasonWriter {
    static func reason(percentiles: [MetricID: Double], metrics: CompanyMetrics) -> String {
        percentiles
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue }
            .prefix(2)
            .map { phrase(for: $0.key, percentile: $0.value, metrics: metrics) }
            .joined(separator: " · ")
    }

    static func phrase(for id: MetricID, percentile: Double, metrics: CompanyMetrics) -> String {
        let top = max(1, Int((100 - percentile).rounded()))
        let raw = metrics[id] ?? 0
        switch id {
        case .revenueCAGR3Y:
            return "Top \(top)% revenue growth"
        case .epsCAGR3Y:
            return "Top \(top)% earnings growth"
        case .growthAcceleration:
            return raw > 0 ? "Growth accelerating" : "Top \(top)% growth trend"
        case .insiderNetBuying:
            let n = metrics.distinctInsiderBuyers
            return n > 0 ? "\(n) insider\(n == 1 ? "" : "s") bought recently" : "Top \(top)% insider activity"
        case .institutionalShareChange:
            return raw > 0 ? "Funds adding shares" : "Top \(top)% fund interest"
        case .holderCountChange:
            return raw > 0 ? "More funds holding" : "Top \(top)% fund interest"
        case .operatingMarginTrend:
            return raw > 0 ? "Margins expanding" : "Top \(top)% margin trend"
        case .freeCashFlowMargin:
            return "Top \(top)% cash generation"
        case .netDebtToFCF:
            return "Low debt"
        case .peg:
            return "PEG \(String(format: "%.1f", raw))"
        }
    }
}
```

- [ ] **Step 5: Implement ScoringEngine and TopPicker**

`StockCore/Sources/StockCore/Scoring/ScoringEngine.swift`:

```swift
public struct ScoringEngine: Sendable {
    public static let insiderBonusBuyers = 3
    public static let insiderBonusPoints = 10.0
    public static let minimumPartsForTop10 = 3

    public init() {}

    public func score(company: Company, metrics: CompanyMetrics, table: PercentileTable) -> ScoreBreakdown {
        var oriented: [MetricID: Double] = [:]
        for (id, value) in metrics.values {
            guard let p = table.percentile(of: value, for: id) else { continue }
            oriented[id] = id.higherIsBetter ? p : 100 - p
        }
        if metrics.distinctInsiderBuyers >= Self.insiderBonusBuyers, let p = oriented[.insiderNetBuying] {
            oriented[.insiderNetBuying] = min(100, p + Self.insiderBonusPoints)
        }

        var partScores: [ScorePart: Double] = [:]
        for part in ScorePart.allCases {
            let ps = MetricID.allCases.filter { $0.part == part }.compactMap { oriented[$0] }
            if !ps.isEmpty { partScores[part] = ps.reduce(0, +) / Double(ps.count) }
        }

        let weightSum = partScores.keys.reduce(0.0) { $0 + $1.weight }
        let total: Double? = weightSum > 0
            ? partScores.reduce(0.0) { $0 + $1.key.weight * $1.value } / weightSum
            : nil

        let losingMoney = (metrics.latestNetIncome ?? 0) < 0 && (metrics.latestFreeCashFlow ?? 0) < 0
        let enoughParts = partScores.count >= Self.minimumPartsForTop10

        return ScoreBreakdown(
            total: total.map { Int($0.rounded()) },
            parts: partScores.mapValues { Int($0.rounded()) },
            metricPercentiles: oriented,
            isEligibleForTop10: enoughParts && !losingMoney && !company.isFinancial,
            limitedData: !enoughParts || company.isFinancial,
            reason: ReasonWriter.reason(percentiles: oriented, metrics: metrics))
    }
}
```

`StockCore/Sources/StockCore/Scoring/TopPicker.swift`:

```swift
public struct RankedPick: Codable, Hashable, Sendable {
    public var rank: Int
    public var ticker: String
    public var name: String
    public var score: Int
    public var reason: String

    public init(rank: Int, ticker: String, name: String, score: Int, reason: String) {
        self.rank = rank
        self.ticker = ticker
        self.name = name
        self.score = score
        self.reason = reason
    }
}

public enum TopPicker {
    public static func pick(_ scored: [(company: Company, score: ScoreBreakdown)], count: Int = 10) -> [RankedPick] {
        let ranked = scored
            .compactMap { entry -> (company: Company, score: ScoreBreakdown, total: Int)? in
                guard entry.score.isEligibleForTop10, let total = entry.score.total else { return nil }
                return (entry.company, entry.score, total)
            }
            .sorted { a, b in
                if a.total != b.total { return a.total > b.total }
                let ga = a.score.parts[.growth] ?? 0, gb = b.score.parts[.growth] ?? 0
                if ga != gb { return ga > gb }
                return a.company.ticker < b.company.ticker
            }
        return ranked.prefix(count).enumerated().map { index, entry in
            RankedPick(rank: index + 1, ticker: entry.company.ticker, name: entry.company.name,
                       score: entry.total, reason: entry.score.reason)
        }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd StockCore && swift test --filter "ScoringEngineTests|TopPickerTests"`
Expected: PASS, 10 tests.

- [ ] **Step 7: Commit**

```bash
git add StockCore
git commit -m "feat(core): score companies, explain rankings and pick the top 10"
```

---

### Task 5: UpsideCalculator

**Files:**
- Create: `StockCore/Sources/StockCore/Scoring/UpsideCalculator.swift`
- Test: `StockCore/Tests/StockCoreTests/UpsideCalculatorTests.swift`

**Interfaces:**
- Consumes: nothing beyond Foundation.
- Produces:
  - `struct UpsideScenario` with `assumedPE: Double, impliedPrice: Double, upside: Double` (0.74 = +74%)
  - `struct UpsideResult` with `growthPath: [Double]`, `ifGrowthContinues: UpsideScenario?`, `ifPEMovesToSectorMedian: UpsideScenario?`, `unavailableReason: String?`
  - `UpsideCalculator.calculate(price: Double?, peTTM: Double?, epsCAGR: Double?, sectorMedianPE: Double?) -> UpsideResult`

- [ ] **Step 1: Write the failing tests**

`StockCore/Tests/StockCoreTests/UpsideCalculatorTests.swift`:

```swift
import Testing
@testable import StockCore

@Suite struct UpsideCalculatorTests {
    @Test func growthIsCappedAndTapered() {
        let r = UpsideCalculator.calculate(price: 100, peTTM: 40, epsCAGR: 0.30, sectorMedianPE: 20)
        #expect(r.unavailableReason == nil)
        #expect(r.growthPath.count == 3)
        #expect(approx(r.growthPath[0], 0.25))
        #expect(approx(r.growthPath[1], 0.20))
        #expect(approx(r.growthPath[2], 0.16))
        #expect(approx(r.ifGrowthContinues?.impliedPrice, 174))
        #expect(approx(r.ifGrowthContinues?.upside, 0.74))
        #expect(r.ifGrowthContinues?.assumedPE == 40)
        #expect(approx(r.ifPEMovesToSectorMedian?.impliedPrice, 87))
        #expect(approx(r.ifPEMovesToSectorMedian?.upside, -0.13))
    }

    @Test func slowGrowthIsNotCapped() {
        let r = UpsideCalculator.calculate(price: 50, peTTM: 20, epsCAGR: 0.10, sectorMedianPE: nil)
        #expect(approx(r.growthPath[0], 0.10))
        #expect(approx(r.ifGrowthContinues?.upside, 1.10 * 1.08 * 1.064 - 1))
        #expect(r.ifPEMovesToSectorMedian == nil)
    }

    @Test func shrinkingEarningsShowDecline() {
        let r = UpsideCalculator.calculate(price: 50, peTTM: 20, epsCAGR: -0.10, sectorMedianPE: 20)
        #expect((r.ifGrowthContinues?.upside ?? 0) < 0)
    }

    @Test func unavailableCasesExplainWhy() {
        let noPrice = UpsideCalculator.calculate(price: nil, peTTM: 20, epsCAGR: 0.1, sectorMedianPE: 20)
        #expect(noPrice.unavailableReason == "No current price is available.")
        #expect(noPrice.ifGrowthContinues == nil)

        let losses = UpsideCalculator.calculate(price: 10, peTTM: -5, epsCAGR: 0.1, sectorMedianPE: 20)
        #expect(losses.unavailableReason == "The company isn't profitable yet, so there's no P/E to project from.")

        let noHistory = UpsideCalculator.calculate(price: 10, peTTM: 15, epsCAGR: nil, sectorMedianPE: 20)
        #expect(noHistory.unavailableReason == "There isn't enough earnings history to estimate growth.")
    }

    @Test func nonPositiveSectorPEIsIgnored() {
        let r = UpsideCalculator.calculate(price: 10, peTTM: 15, epsCAGR: 0.1, sectorMedianPE: 0)
        #expect(r.ifGrowthContinues != nil)
        #expect(r.ifPEMovesToSectorMedian == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd StockCore && swift test --filter UpsideCalculatorTests`
Expected: build FAILS with `cannot find 'UpsideCalculator' in scope`.

- [ ] **Step 3: Implement UpsideCalculator**

`StockCore/Sources/StockCore/Scoring/UpsideCalculator.swift`:

```swift
import Foundation

public struct UpsideScenario: Codable, Hashable, Sendable {
    public var assumedPE: Double
    public var impliedPrice: Double
    /// Fractional change from today's price: 0.74 means +74%.
    public var upside: Double

    public init(assumedPE: Double, impliedPrice: Double, upside: Double) {
        self.assumedPE = assumedPE
        self.impliedPrice = impliedPrice
        self.upside = upside
    }
}

public struct UpsideResult: Codable, Hashable, Sendable {
    /// Assumed EPS growth for each of the next three years.
    public var growthPath: [Double]
    public var ifGrowthContinues: UpsideScenario?
    public var ifPEMovesToSectorMedian: UpsideScenario?
    public var unavailableReason: String?

    public init(growthPath: [Double], ifGrowthContinues: UpsideScenario?,
                ifPEMovesToSectorMedian: UpsideScenario?, unavailableReason: String?) {
        self.growthPath = growthPath
        self.ifGrowthContinues = ifGrowthContinues
        self.ifPEMovesToSectorMedian = ifPEMovesToSectorMedian
        self.unavailableReason = unavailableReason
    }

    static func unavailable(_ reason: String) -> UpsideResult {
        UpsideResult(growthPath: [], ifGrowthContinues: nil, ifPEMovesToSectorMedian: nil,
                     unavailableReason: reason)
    }
}

/// Scenarios, not predictions: "if earnings keep growing like this, and the market
/// values them at this P/E, the price in 3 years would be about X".
public enum UpsideCalculator {
    public static let growthCap = 0.25
    public static let taper = 0.8
    public static let years = 3

    public static func calculate(price: Double?, peTTM: Double?, epsCAGR: Double?,
                                 sectorMedianPE: Double?) -> UpsideResult {
        guard let price, price > 0 else {
            return .unavailable("No current price is available.")
        }
        guard let pe = peTTM, pe > 0 else {
            return .unavailable("The company isn't profitable yet, so there's no P/E to project from.")
        }
        guard let growth = epsCAGR else {
            return .unavailable("There isn't enough earnings history to estimate growth.")
        }

        let start = min(growth, growthCap)
        let path = (0..<years).map { start * pow(taper, Double($0)) }
        let factor = path.reduce(1.0) { $0 * (1 + $1) }
        let eps = price / pe

        func scenario(_ multiple: Double) -> UpsideScenario {
            let implied = eps * factor * multiple
            return UpsideScenario(assumedPE: multiple, impliedPrice: implied, upside: implied / price - 1)
        }

        let sector = sectorMedianPE.flatMap { $0 > 0 ? scenario($0) : nil }
        return UpsideResult(growthPath: path, ifGrowthContinues: scenario(pe),
                            ifPEMovesToSectorMedian: sector, unavailableReason: nil)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd StockCore && swift test --filter UpsideCalculatorTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add StockCore
git commit -m "feat(core): add 3-year upside scenarios"
```

---

### Task 6: Networking — transport, rate limiter, EDGAR client

**Files:**
- Create: `StockCore/Sources/StockCore/Networking/StockCoreError.swift`
- Create: `StockCore/Sources/StockCore/Networking/HTTPTransport.swift`
- Create: `StockCore/Sources/StockCore/Networking/RateLimiter.swift`
- Create: `StockCore/Sources/StockCore/Networking/EDGARClient.swift`
- Create: `StockCore/Tests/StockCoreTests/Support/StubTransport.swift`
- Test: `StockCore/Tests/StockCoreTests/NetworkingTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `enum StockCoreError: Error, Equatable` with `http(status: Int, url: String)`, `missingData(String)`, `malformed(String)`
  - `struct HTTPResponse { status: Int; body: Data }`
  - `protocol HTTPTransport: Sendable { func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse }`
  - `URLSessionTransport()`
  - `actor RateLimiter { init(requestsPerSecond: Double); func acquire() async }`
  - `EDGARClient(userAgent: String, transport: any HTTPTransport = URLSessionTransport(), limiter: RateLimiter = RateLimiter(requestsPerSecond: 8), maxRetries: Int = 4, baseBackoff: Duration = .seconds(10))`, `func get(_ url: URL) async throws -> Data`
  - Test support: `StubTransport` with `respond(_ url: String, status: Int = 200, body: Data)`, `respond(_ url: String, statuses: [Int])`, `requestedURLs: [String]`, `requests: [StubTransport.Request]`; unknown URLs return 404. Test helper `testEDGARClient(_ stub: StubTransport) -> EDGARClient`.

- [ ] **Step 1: Write the stub transport**

`StockCore/Tests/StockCoreTests/Support/StubTransport.swift`:

```swift
import Foundation
@testable import StockCore

/// In-memory HTTP: each URL has a queue of responses; the last one repeats.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    struct Request: Sendable {
        let url: String
        let headers: [String: String]
    }

    private let lock = NSLock()
    private var routes: [String: [HTTPResponse]] = [:]
    private var log: [Request] = []

    func respond(_ url: String, status: Int = 200, body: Data) {
        lock.withLock { routes[url] = [HTTPResponse(status: status, body: body)] }
    }

    func respond(_ url: String, statuses: [Int], body: Data = Data()) {
        lock.withLock { routes[url] = statuses.map { HTTPResponse(status: $0, body: body) } }
    }

    var requests: [Request] { lock.withLock { log } }
    var requestedURLs: [String] { requests.map(\.url) }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        lock.withLock {
            log.append(Request(url: url.absoluteString, headers: headers))
            guard var queue = routes[url.absoluteString], !queue.isEmpty else {
                return HTTPResponse(status: 404, body: Data())
            }
            let response = queue.count > 1 ? queue.removeFirst() : queue[0]
            routes[url.absoluteString] = queue
            return response
        }
    }
}

func testEDGARClient(_ stub: StubTransport) -> EDGARClient {
    EDGARClient(userAgent: "StockWatcher test@example.com", transport: stub,
                limiter: RateLimiter(requestsPerSecond: 1_000), maxRetries: 2,
                baseBackoff: .milliseconds(1))
}
```

- [ ] **Step 2: Write the failing networking tests**

`StockCore/Tests/StockCoreTests/NetworkingTests.swift`:

```swift
import Foundation
import Testing
@testable import StockCore

@Suite struct NetworkingTests {
    let url = URL(string: "https://data.sec.gov/submissions/CIK0000123456.json")!

    @Test func edgarClientSendsUserAgentAndReturnsBody() async throws {
        let stub = StubTransport()
        stub.respond(url.absoluteString, body: Data("ok".utf8))
        let data = try await testEDGARClient(stub).get(url)
        #expect(String(decoding: data, as: UTF8.self) == "ok")
        #expect(stub.requests.first?.headers["User-Agent"] == "StockWatcher test@example.com")
    }

    @Test func edgarClientRetriesRateLimitAndServerErrors() async throws {
        let stub = StubTransport()
        stub.respond(url.absoluteString, statuses: [429, 503, 200], body: Data("ok".utf8))
        let data = try await testEDGARClient(stub).get(url)
        #expect(String(decoding: data, as: UTF8.self) == "ok")
        #expect(stub.requestedURLs.count == 3)
    }

    @Test func edgarClientGivesUpAfterMaxRetries() async {
        let stub = StubTransport()
        stub.respond(url.absoluteString, statuses: [403])
        await #expect(throws: StockCoreError.http(status: 403, url: url.absoluteString)) {
            try await testEDGARClient(stub).get(url)
        }
        #expect(stub.requestedURLs.count == 3)  // first try + 2 retries
    }

    @Test func edgarClientDoesNotRetryNotFound() async {
        let stub = StubTransport()
        await #expect(throws: StockCoreError.http(status: 404, url: url.absoluteString)) {
            try await testEDGARClient(stub).get(url)
        }
        #expect(stub.requestedURLs.count == 1)
    }

    @Test func rateLimiterSpacesRequests() async {
        let limiter = RateLimiter(requestsPerSecond: 20)  // 50 ms apart
        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            for _ in 0..<4 { await limiter.acquire() }
        }
        #expect(elapsed >= .milliseconds(140))
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd StockCore && swift test --filter NetworkingTests`
Expected: build FAILS with `cannot find type 'HTTPTransport' in scope`.

- [ ] **Step 4: Implement errors and transport**

`StockCore/Sources/StockCore/Networking/StockCoreError.swift`:

```swift
public enum StockCoreError: Error, Equatable, Sendable {
    case http(status: Int, url: String)
    case missingData(String)
    case malformed(String)
}
```

`StockCore/Sources/StockCore/Networking/HTTPTransport.swift`:

```swift
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPResponse: Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

public protocol HTTPTransport: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        // Continuation form works on both Apple platforms and Linux FoundationNetworking.
        return try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                continuation.resume(returning: HTTPResponse(status: status, body: data ?? Data()))
            }.resume()
        }
    }
}
```

- [ ] **Step 5: Implement RateLimiter and EDGARClient**

`StockCore/Sources/StockCore/Networking/RateLimiter.swift`:

```swift
/// Hands out evenly spaced time slots. The slot is reserved before sleeping,
/// so concurrent callers never share one.
public actor RateLimiter {
    private let interval: Duration
    private let clock = ContinuousClock()
    private var nextSlot: ContinuousClock.Instant

    public init(requestsPerSecond: Double) {
        let nanos = Int64((1_000_000_000 / requestsPerSecond).rounded())
        interval = .nanoseconds(nanos)
        nextSlot = clock.now
    }

    public func acquire() async {
        let now = clock.now
        let slot = max(now, nextSlot)
        nextSlot = slot + interval
        if slot > now {
            try? await Task.sleep(until: slot, clock: clock)
        }
    }
}
```

`StockCore/Sources/StockCore/Networking/EDGARClient.swift`:

```swift
import Foundation

/// SEC EDGAR access: declared User-Agent, ≤ 8 requests/second, exponential
/// backoff on 403/429/5xx (SEC uses 403 when it throttles).
/// Share one client per process: the rate limit lives in its `RateLimiter`.
public struct EDGARClient: Sendable {
    public let userAgent: String
    let transport: any HTTPTransport
    let limiter: RateLimiter
    let maxRetries: Int
    let baseBackoff: Duration

    public init(userAgent: String,
                transport: any HTTPTransport = URLSessionTransport(),
                limiter: RateLimiter = RateLimiter(requestsPerSecond: 8),
                maxRetries: Int = 4,
                baseBackoff: Duration = .seconds(10)) {
        self.userAgent = userAgent
        self.transport = transport
        self.limiter = limiter
        self.maxRetries = maxRetries
        self.baseBackoff = baseBackoff
    }

    public func get(_ url: URL) async throws -> Data {
        var attempt = 0
        while true {
            await limiter.acquire()
            let response = try await transport.get(url, headers: ["User-Agent": userAgent])
            if (200..<300).contains(response.status) {
                return response.body
            }
            let retryable = response.status == 403 || response.status == 429
                || (500..<600).contains(response.status)
            if retryable && attempt < maxRetries {
                try await Task.sleep(for: baseBackoff * (1 << attempt))
                attempt += 1
                continue
            }
            throw StockCoreError.http(status: response.status, url: url.absoluteString)
        }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd StockCore && swift test --filter NetworkingTests`
Expected: PASS, 5 tests.

- [ ] **Step 7: Commit**

```bash
git add StockCore
git commit -m "feat(core): add HTTP transport, rate limiter and EDGAR client with backoff"
```

---

### Task 7: EDGAR URLs, company directory, submissions

**Files:**
- Create: `StockCore/Sources/StockCore/EDGAR/EDGARURL.swift`
- Create: `StockCore/Sources/StockCore/EDGAR/CompanyDirectory.swift`
- Create: `StockCore/Sources/StockCore/EDGAR/EDGARSubmissions.swift`
- Create: `StockCore/Tests/StockCoreTests/Fixtures/company_tickers_sample.json`
- Create: `StockCore/Tests/StockCoreTests/Fixtures/submissions_sample.json`
- Test: `StockCore/Tests/StockCoreTests/EDGARDirectoryTests.swift`

**Interfaces:**
- Consumes: `StockCoreError` (Task 6), `Fixture` (Task 1).
- Produces:
  - `EDGARURL.companyTickers: URL`, `EDGARURL.paddedCIK(_ cik: Int) -> String`, `EDGARURL.submissions(cik:) -> URL`, `EDGARURL.companyFacts(cik:) -> URL`, `EDGARURL.filingDocument(cik:accession:primaryDocument:) -> URL`
  - `DirectoryEntry(ticker: String, cik: Int, name: String)`
  - `CompanyDirectory(entries:)`, `CompanyDirectory(secTickersJSON: Data) throws`, `static normalize(_ ticker: String) -> String` (`"brk.b"` → `"BRK-B"`), `lookup(ticker:) -> DirectoryEntry?`, `search(_ query: String, limit: Int = 20) -> [DirectoryEntry]`
  - `FilingRef(accessionNumber:filingDate:form:primaryDocument:)`
  - `EDGARSubmissions(jsonData: Data) throws` with `name`, `sicCode: Int?`, `sicDescription: String?`, `recentFilings: [FilingRef]`

- [ ] **Step 1: Add fixtures**

`StockCore/Tests/StockCoreTests/Fixtures/company_tickers_sample.json`:

```json
{
  "0": {"cik_str": 1045810, "ticker": "NVDA", "title": "NVIDIA CORP"},
  "1": {"cik_str": 1652044, "ticker": "GOOGL", "title": "Alphabet Inc."},
  "2": {"cik_str": 1652044, "ticker": "GOOG", "title": "Alphabet Inc."},
  "3": {"cik_str": 1067983, "ticker": "BRK-B", "title": "BERKSHIRE HATHAWAY INC"},
  "4": {"cik_str": 320193, "ticker": "AAPL", "title": "Apple Inc."},
  "5": {"cik_str": 999999, "ticker": "AAPL", "title": "Duplicate Should Be Ignored"}
}
```

`StockCore/Tests/StockCoreTests/Fixtures/submissions_sample.json`:

```json
{
  "cik": "0000123456",
  "entityType": "operating",
  "sic": "3674",
  "sicDescription": "Semiconductors & Related Devices",
  "name": "Sample Corp",
  "tickers": ["SMPL"],
  "filings": {
    "recent": {
      "accessionNumber": ["0000123456-26-000050", "0000123456-26-000040", "0000123456-26-000030", "0000123456-25-000010"],
      "filingDate": ["2026-08-15", "2026-08-01", "2026-06-02", "2025-11-20"],
      "reportDate": ["2026-08-12", "2026-06-30", "2026-05-29", "2025-11-18"],
      "form": ["4", "10-Q", "4", "4"],
      "primaryDocument": ["xslF345X05/form4-aug.xml", "smpl-20260630.htm", "xslF345X05/form4-jun.xml", "xslF345X05/form4-old.xml"]
    },
    "files": []
  }
}
```

- [ ] **Step 2: Write the failing tests**

`StockCore/Tests/StockCoreTests/EDGARDirectoryTests.swift`:

```swift
import Foundation
import Testing
@testable import StockCore

@Suite struct EDGARDirectoryTests {
    @Test func buildsEDGARURLs() {
        #expect(EDGARURL.paddedCIK(320193) == "0000320193")
        #expect(EDGARURL.submissions(cik: 123456).absoluteString
                == "https://data.sec.gov/submissions/CIK0000123456.json")
        #expect(EDGARURL.companyFacts(cik: 123456).absoluteString
                == "https://data.sec.gov/api/xbrl/companyfacts/CIK0000123456.json")
    }

    @Test func filingDocumentStripsXSLRendererPrefix() {
        let url = EDGARURL.filingDocument(cik: 123456, accession: "0000123456-26-000050",
                                          primaryDocument: "xslF345X05/form4-aug.xml")
        #expect(url.absoluteString
                == "https://www.sec.gov/Archives/edgar/data/123456/000012345626000050/form4-aug.xml")
        let plain = EDGARURL.filingDocument(cik: 1, accession: "0000000001-26-000001",
                                            primaryDocument: "doc.xml")
        #expect(plain.absoluteString.hasSuffix("/000000000126000001/doc.xml"))
    }

    @Test func lookupNormalizesClassShareTickers() throws {
        let dir = try CompanyDirectory(secTickersJSON: Fixture.data("company_tickers_sample.json"))
        #expect(dir.lookup(ticker: "BRK.B")?.cik == 1067983)
        #expect(dir.lookup(ticker: "brk-b")?.cik == 1067983)
        #expect(dir.lookup(ticker: " BRK/B ")?.cik == 1067983)
        #expect(dir.lookup(ticker: "ZZZZ") == nil)
    }

    @Test func duplicateTickersKeepTheFirstRow() throws {
        let dir = try CompanyDirectory(secTickersJSON: Fixture.data("company_tickers_sample.json"))
        #expect(dir.lookup(ticker: "AAPL")?.cik == 320193)
    }

    @Test func searchRanksExactThenPrefixThenName() throws {
        let dir = try CompanyDirectory(secTickersJSON: Fixture.data("company_tickers_sample.json"))
        #expect(dir.search("goog").map(\.ticker) == ["GOOG", "GOOGL"])
        #expect(dir.search("alphabet").map(\.ticker) == ["GOOGL", "GOOG"])
        #expect(dir.search("nvidia", limit: 1).map(\.ticker) == ["NVDA"])
        #expect(dir.search("  ").isEmpty)
    }

    @Test func parsesSubmissions() throws {
        let s = try EDGARSubmissions(jsonData: Fixture.data("submissions_sample.json"))
        #expect(s.name == "Sample Corp")
        #expect(s.sicCode == 3674)
        #expect(s.sicDescription == "Semiconductors & Related Devices")
        #expect(s.recentFilings.count == 4)
        #expect(s.recentFilings[0] == FilingRef(accessionNumber: "0000123456-26-000050",
                                                filingDate: "2026-08-15", form: "4",
                                                primaryDocument: "xslF345X05/form4-aug.xml"))
    }

    @Test func emptySICBecomesNil() throws {
        let json = #"{"name":"X","sic":"","sicDescription":"","filings":{"recent":{"accessionNumber":[],"filingDate":[],"form":[],"primaryDocument":[]}}}"#
        let s = try EDGARSubmissions(jsonData: Data(json.utf8))
        #expect(s.sicCode == nil)
        #expect(s.sicDescription == nil)
    }

    @Test func malformedSubmissionsThrow() {
        #expect(throws: StockCoreError.self) { try EDGARSubmissions(jsonData: Data("nope".utf8)) }
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd StockCore && swift test --filter EDGARDirectoryTests`
Expected: build FAILS with `cannot find 'EDGARURL' in scope`.

- [ ] **Step 4: Implement EDGARURL**

`StockCore/Sources/StockCore/EDGAR/EDGARURL.swift`:

```swift
import Foundation

public enum EDGARURL {
    public static let companyTickers = URL(string: "https://www.sec.gov/files/company_tickers.json")!

    public static func paddedCIK(_ cik: Int) -> String {
        let digits = String(cik)
        return String(repeating: "0", count: max(0, 10 - digits.count)) + digits
    }

    public static func submissions(cik: Int) -> URL {
        URL(string: "https://data.sec.gov/submissions/CIK\(paddedCIK(cik)).json")!
    }

    public static func companyFacts(cik: Int) -> URL {
        URL(string: "https://data.sec.gov/api/xbrl/companyfacts/CIK\(paddedCIK(cik)).json")!
    }

    /// Raw filing document. EDGAR lists Form 4s as "xslF345X05/file.xml" (an HTML
    /// rendering); dropping the xsl folder gives the original XML.
    public static func filingDocument(cik: Int, accession: String, primaryDocument: String) -> URL {
        var parts = primaryDocument.split(separator: "/").map(String.init)
        if parts.count > 1, parts[0].hasPrefix("xsl") {
            parts.removeFirst()
        }
        let folder = accession.replacingOccurrences(of: "-", with: "")
        return URL(string: "https://www.sec.gov/Archives/edgar/data/\(cik)/\(folder)/\(parts.joined(separator: "/"))")!
    }
}
```

- [ ] **Step 5: Implement CompanyDirectory and EDGARSubmissions**

`StockCore/Sources/StockCore/EDGAR/CompanyDirectory.swift`:

```swift
import Foundation

public struct DirectoryEntry: Codable, Hashable, Sendable {
    public var ticker: String
    public var cik: Int
    public var name: String

    public init(ticker: String, cik: Int, name: String) {
        self.ticker = ticker
        self.cik = cik
        self.name = name
    }
}

/// Ticker ↔ CIK map from the SEC's company_tickers.json.
public struct CompanyDirectory: Sendable {
    public let entries: [DirectoryEntry]
    private let byTicker: [String: DirectoryEntry]

    public init(entries: [DirectoryEntry]) {
        self.entries = entries
        var map: [String: DirectoryEntry] = [:]
        for entry in entries where map[Self.normalize(entry.ticker)] == nil {
            map[Self.normalize(entry.ticker)] = entry
        }
        byTicker = map
    }

    public init(secTickersJSON data: Data) throws {
        struct Row: Decodable {
            let cik_str: Int
            let ticker: String
            let title: String
        }
        let rows: [String: Row]
        do {
            rows = try JSONDecoder().decode([String: Row].self, from: data)
        } catch {
            throw StockCoreError.malformed("company_tickers.json: \(error)")
        }
        // The SEC file is keyed "0", "1", … roughly by size; keep that order so
        // the first row wins when a ticker appears twice.
        let entries = rows
            .sorted { (Int($0.key) ?? .max) < (Int($1.key) ?? .max) }
            .map { DirectoryEntry(ticker: $0.value.ticker, cik: $0.value.cik_str, name: $0.value.title) }
        self.init(entries: entries)
    }

    /// EDGAR style: uppercase, class separator "-" ("brk.b" → "BRK-B").
    public static func normalize(_ ticker: String) -> String {
        ticker.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }

    public func lookup(ticker: String) -> DirectoryEntry? {
        byTicker[Self.normalize(ticker)]
    }

    /// Exact ticker, then ticker prefix, then name contains — deduplicated.
    public func search(_ query: String, limit: Int = 20) -> [DirectoryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, limit > 0 else { return [] }
        let normalized = Self.normalize(trimmed)

        let exact = entries.filter { Self.normalize($0.ticker) == normalized }
        let prefix = entries
            .filter { Self.normalize($0.ticker).hasPrefix(normalized) && Self.normalize($0.ticker) != normalized }
            .sorted { $0.ticker < $1.ticker }
        let byName = entries.filter { $0.name.range(of: trimmed, options: .caseInsensitive) != nil }

        var seen = Set<String>()
        var results: [DirectoryEntry] = []
        for entry in exact + prefix + byName where seen.insert(entry.ticker).inserted {
            results.append(entry)
            if results.count == limit { break }
        }
        return results
    }
}
```

`StockCore/Sources/StockCore/EDGAR/EDGARSubmissions.swift`:

```swift
import Foundation

public struct FilingRef: Codable, Hashable, Sendable {
    public var accessionNumber: String
    public var filingDate: String
    public var form: String
    public var primaryDocument: String

    public init(accessionNumber: String, filingDate: String, form: String, primaryDocument: String) {
        self.accessionNumber = accessionNumber
        self.filingDate = filingDate
        self.form = form
        self.primaryDocument = primaryDocument
    }
}

/// data.sec.gov/submissions/CIK##########.json — company profile and recent filings.
public struct EDGARSubmissions: Sendable {
    public var name: String
    public var sicCode: Int?
    public var sicDescription: String?
    /// Newest first, as EDGAR returns them.
    public var recentFilings: [FilingRef]

    private struct DTO: Decodable {
        let name: String
        let sic: String?
        let sicDescription: String?
        let filings: Filings

        struct Filings: Decodable { let recent: Recent }
        struct Recent: Decodable {
            let accessionNumber: [String]
            let filingDate: [String]
            let form: [String]
            let primaryDocument: [String]
        }
    }

    public init(jsonData: Data) throws {
        let dto: DTO
        do {
            dto = try JSONDecoder().decode(DTO.self, from: jsonData)
        } catch {
            throw StockCoreError.malformed("submissions: \(error)")
        }
        let recent = dto.filings.recent
        let count = min(recent.accessionNumber.count, recent.filingDate.count,
                        recent.form.count, recent.primaryDocument.count)
        name = dto.name
        sicCode = dto.sic.flatMap { Int($0) }
        sicDescription = dto.sicDescription.flatMap { $0.isEmpty ? nil : $0 }
        recentFilings = (0..<count).map {
            FilingRef(accessionNumber: recent.accessionNumber[$0], filingDate: recent.filingDate[$0],
                      form: recent.form[$0], primaryDocument: recent.primaryDocument[$0])
        }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd StockCore && swift test --filter EDGARDirectoryTests`
Expected: PASS, 8 tests.

- [ ] **Step 7: Commit**

```bash
git add StockCore
git commit -m "feat(core): add EDGAR URLs, ticker directory and submissions parsing"
```

---

### Task 8: XBRL company facts parser

**Files:**
- Create: `StockCore/Sources/StockCore/EDGAR/CompanyFactsParser.swift`
- Create: `StockCore/Tests/StockCoreTests/Fixtures/companyfacts_sample.json`
- Test: `StockCore/Tests/StockCoreTests/CompanyFactsParserTests.swift`

**Interfaces:**
- Consumes: `AnnualFinancials`, `ISODay` (Task 1), `StockCoreError` (Task 6).
- Produces: `CompanyFactsParser.annualFinancials(from: Data, maxYears: Int = 5) throws -> [AnnualFinancials]` (oldest → newest; period ends come from revenue, or net income if revenue is absent).

- [ ] **Step 1: Add the fixture**

`StockCore/Tests/StockCoreTests/Fixtures/companyfacts_sample.json` — covers a tag switch, a restatement, a Q4 figure inside a 10-K, and a 10-Q:

```json
{
  "cik": 123456,
  "entityName": "Sample Corp",
  "facts": {
    "dei": {
      "EntityCommonStockSharesOutstanding": {"label": "Shares", "units": {"shares": [
        {"end": "2025-01-31", "val": 1000000, "accn": "a", "fy": 2024, "fp": "FY", "form": "10-K", "filed": "2025-02-10"}
      ]}}
    },
    "us-gaap": {
      "Revenues": {"label": "Revenues", "units": {"USD": [
        {"start": "2020-01-01", "end": "2020-12-31", "val": 80, "accn": "a", "fy": 2020, "fp": "FY", "form": "10-K", "filed": "2021-02-10"},
        {"start": "2021-01-01", "end": "2021-12-31", "val": 99, "accn": "b", "fy": 2021, "fp": "FY", "form": "10-K", "filed": "2022-02-10"}
      ]}},
      "RevenueFromContractWithCustomerExcludingAssessedTax": {"label": "Revenue", "units": {"USD": [
        {"start": "2021-01-01", "end": "2021-12-31", "val": 100, "accn": "c", "fy": 2022, "fp": "FY", "form": "10-K", "filed": "2023-02-10", "frame": "CY2021"},
        {"start": "2022-01-01", "end": "2022-12-31", "val": 120, "accn": "c", "fy": 2022, "fp": "FY", "form": "10-K", "filed": "2023-02-10", "frame": "CY2022"},
        {"start": "2023-01-01", "end": "2023-12-31", "val": 150, "accn": "d", "fy": 2023, "fp": "FY", "form": "10-K", "filed": "2024-02-10"},
        {"start": "2023-01-01", "end": "2023-12-31", "val": 151, "accn": "e", "fy": 2023, "fp": "FY", "form": "10-K/A", "filed": "2024-06-01"},
        {"start": "2024-01-01", "end": "2024-03-31", "val": 40, "accn": "f", "fy": 2024, "fp": "Q1", "form": "10-Q", "filed": "2024-05-01"},
        {"start": "2024-01-01", "end": "2024-12-31", "val": 190, "accn": "g", "fy": 2024, "fp": "FY", "form": "10-K", "filed": "2025-02-10", "frame": "CY2024"},
        {"start": "2024-10-01", "end": "2024-12-31", "val": 55, "accn": "g", "fy": 2024, "fp": "FY", "form": "10-K", "filed": "2025-02-10", "frame": "CY2024Q4"}
      ]}},
      "EarningsPerShareDiluted": {"label": "EPS diluted", "units": {"USD/shares": [
        {"start": "2021-01-01", "end": "2021-12-31", "val": 1.00, "accn": "c", "fy": 2022, "fp": "FY", "form": "10-K", "filed": "2023-02-10"},
        {"start": "2022-01-01", "end": "2022-12-31", "val": 1.30, "accn": "c", "fy": 2022, "fp": "FY", "form": "10-K", "filed": "2023-02-10"},
        {"start": "2023-01-01", "end": "2023-12-31", "val": 1.60, "accn": "d", "fy": 2023, "fp": "FY", "form": "10-K", "filed": "2024-02-10"},
        {"start": "2024-01-01", "end": "2024-12-31", "val": 2.10, "accn": "g", "fy": 2024, "fp": "FY", "form": "10-K", "filed": "2025-02-10"}
      ]}},
      "NetIncomeLoss": {"label": "Net income", "units": {"USD": [
        {"start": "2021-01-01", "end": "2021-12-31", "val": 10, "accn": "c", "fy": 2022, "fp": "FY", "form": "10-K", "filed": "2023-02-10"},
        {"start": "2024-01-01", "end": "2024-12-31", "val": 21, "accn": "g", "fy": 2024, "fp": "FY", "form": "10-K", "filed": "2025-02-10"}
      ]}},
      "OperatingIncomeLoss": {"label": "Operating income", "units": {"USD": [
        {"start": "2024-01-01", "end": "2024-12-31", "val": 34, "accn": "g", "fy": 2024, "fp": "FY", "form": "10-K", "filed": "2025-02-10"}
      ]}},
      "NetCashProvidedByUsedInOperatingActivities": {"label": "OCF", "units": {"USD": [
        {"start": "2024-01-01", "end": "2024-12-31", "val": 30, "accn": "g", "fy": 2024, "fp": "FY", "form": "10-K", "filed": "2025-02-10"}
      ]}},
      "PaymentsToAcquirePropertyPlantAndEquipment": {"label": "Capex", "units": {"USD": [
        {"start": "2024-01-01", "end": "2024-12-31", "val": 8, "accn": "g", "fy": 2024, "fp": "FY", "form": "10-K", "filed": "2025-02-10"}
      ]}},
      "LongTermDebt": {"label": "Debt", "units": {"USD": [
        {"end": "2023-12-31", "val": 50, "accn": "d", "fy": 2023, "fp": "FY", "form": "10-K", "filed": "2024-02-10"},
        {"end": "2024-06-30", "val": 48, "accn": "h", "fy": 2024, "fp": "Q2", "form": "10-Q", "filed": "2024-08-01"},
        {"end": "2024-12-31", "val": 45, "accn": "g", "fy": 2024, "fp": "FY", "form": "10-K", "filed": "2025-02-10"}
      ]}},
      "CashAndCashEquivalentsAtCarryingValue": {"label": "Cash", "units": {"USD": [
        {"end": "2024-12-31", "val": 20, "accn": "g", "fy": 2024, "fp": "FY", "form": "10-K", "filed": "2025-02-10"}
      ]}}
    }
  }
}
```

- [ ] **Step 2: Write the failing tests**

`StockCore/Tests/StockCoreTests/CompanyFactsParserTests.swift`:

```swift
import Foundation
import Testing
@testable import StockCore

@Suite struct CompanyFactsParserTests {
    func parse(maxYears: Int = 5) throws -> [AnnualFinancials] {
        try CompanyFactsParser.annualFinancials(from: Fixture.data("companyfacts_sample.json"),
                                                maxYears: maxYears)
    }

    @Test func mergesRevenueTagsAcrossATagSwitch() throws {
        let years = try parse()
        #expect(years.map(\.periodEnd) == ["2020-12-31", "2021-12-31", "2022-12-31", "2023-12-31", "2024-12-31"])
        #expect(years[0].revenue == 80)    // only in the old "Revenues" tag
        #expect(years[1].revenue == 100)   // priority tag beats the old tag's 99
    }

    @Test func latestFiledValueWinsForRestatements() throws {
        #expect(try parse()[3].revenue == 151)
    }

    @Test func ignoresQuarterlyFactsInsideAnnualFilings() throws {
        #expect(try parse().last?.revenue == 190)
    }

    @Test func fillsEveryFieldForTheLatestYear() throws {
        let latest = try #require(try parse().last)
        #expect(latest.epsDiluted == 2.10)
        #expect(latest.netIncome == 21)
        #expect(latest.operatingIncome == 34)
        #expect(latest.operatingCashFlow == 30)
        #expect(latest.capitalExpenditure == 8)
        #expect(latest.freeCashFlow == 22)
        #expect(latest.longTermDebt == 45)
        #expect(latest.cash == 20)
    }

    @Test func balanceSheetValuesComeFromAnnualReportsOnly() throws {
        let years = try parse()
        #expect(years[3].longTermDebt == 50)
        #expect(years[3].cash == nil)
    }

    @Test func limitsToMostRecentYears() throws {
        #expect(try parse(maxYears: 4).map(\.periodEnd).first == "2021-12-31")
    }

    @Test func companyWithoutUSGAAPFactsHasNoYears() throws {
        let json = #"{"cik":1,"entityName":"Shell","facts":{"dei":{}}}"#
        #expect(try CompanyFactsParser.annualFinancials(from: Data(json.utf8)).isEmpty)
    }

    @Test func malformedJSONThrows() {
        #expect(throws: StockCoreError.self) {
            try CompanyFactsParser.annualFinancials(from: Data("not json".utf8))
        }
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd StockCore && swift test --filter CompanyFactsParserTests`
Expected: build FAILS with `cannot find 'CompanyFactsParser' in scope`.

- [ ] **Step 4: Implement the parser**

`StockCore/Sources/StockCore/EDGAR/CompanyFactsParser.swift`:

```swift
import Foundation

/// data.sec.gov/api/xbrl/companyfacts → one AnnualFinancials per fiscal year.
public enum CompanyFactsParser {
    static let revenueTags = [
        "RevenueFromContractWithCustomerExcludingAssessedTax",
        "Revenues",
        "SalesRevenueNet",
        "RevenueFromContractWithCustomerIncludingAssessedTax",
    ]
    static let netIncomeTags = ["NetIncomeLoss", "ProfitLoss"]
    static let operatingIncomeTags = ["OperatingIncomeLoss"]
    static let epsTags = ["EarningsPerShareDiluted", "EarningsPerShareBasic"]
    static let operatingCashFlowTags = [
        "NetCashProvidedByUsedInOperatingActivities",
        "NetCashProvidedByUsedInOperatingActivitiesContinuingOperations",
    ]
    static let capexTags = ["PaymentsToAcquirePropertyPlantAndEquipment", "PaymentsToAcquireProductiveAssets"]
    static let debtTags = ["LongTermDebt", "LongTermDebtNoncurrent"]
    static let cashTags = [
        "CashAndCashEquivalentsAtCarryingValue",
        "CashCashEquivalentsRestrictedCashAndRestrictedCashEquivalents",
    ]

    /// Fiscal years run 52 or 53 weeks; anything outside this is a quarter or a transition period.
    static let annualDurationDays = 350...380

    private struct DTO: Decodable {
        let facts: [String: [String: Concept]]
    }
    private struct Concept: Decodable {
        let units: [String: [Fact]]
    }
    private struct Fact: Decodable {
        let start: String?
        let end: String
        let val: Double
        let form: String?
        let filed: String
    }

    public static func annualFinancials(from data: Data, maxYears: Int = 5) throws -> [AnnualFinancials] {
        let dto: DTO
        do {
            dto = try JSONDecoder().decode(DTO.self, from: data)
        } catch {
            throw StockCoreError.malformed("companyfacts: \(error)")
        }
        let gaap = dto.facts["us-gaap"] ?? [:]

        let revenue = durations(gaap, revenueTags)
        let netIncome = durations(gaap, netIncomeTags)
        let operatingIncome = durations(gaap, operatingIncomeTags)
        let eps = durations(gaap, epsTags, unit: "USD/shares")
        let operatingCashFlow = durations(gaap, operatingCashFlowTags)
        let capex = durations(gaap, capexTags)
        let debt = instants(gaap, debtTags)
        let cash = instants(gaap, cashTags)

        let anchor = revenue.isEmpty ? netIncome : revenue
        return anchor.keys.sorted().suffix(maxYears).map { end in
            AnnualFinancials(periodEnd: end, revenue: revenue[end], netIncome: netIncome[end],
                             operatingIncome: operatingIncome[end], epsDiluted: eps[end],
                             operatingCashFlow: operatingCashFlow[end], capitalExpenditure: capex[end],
                             longTermDebt: debt[end], cash: cash[end])
        }
    }

    private static func durations(_ gaap: [String: Concept], _ tags: [String], unit: String = "USD") -> [String: Double] {
        merged(tags.map { annualFacts(gaap[$0]?.units[unit] ?? [], instant: false) })
    }

    private static func instants(_ gaap: [String: Concept], _ tags: [String], unit: String = "USD") -> [String: Double] {
        merged(tags.map { annualFacts(gaap[$0]?.units[unit] ?? [], instant: true) })
    }

    /// Period end → value, keeping only annual-report facts and the latest filing per period.
    private static func annualFacts(_ facts: [Fact], instant: Bool) -> [String: Double] {
        var best: [String: Fact] = [:]
        for fact in facts {
            guard let form = fact.form, form.hasPrefix("10-K") else { continue }
            if instant {
                guard fact.start == nil else { continue }
            } else {
                guard let start = fact.start,
                      let days = ISODay.days(from: start, to: fact.end),
                      annualDurationDays.contains(days) else { continue }
            }
            if let current = best[fact.end], current.filed >= fact.filed { continue }
            best[fact.end] = fact
        }
        return best.mapValues(\.val)
    }

    /// Earlier maps win: tags are listed in priority order.
    private static func merged(_ maps: [[String: Double]]) -> [String: Double] {
        var out: [String: Double] = [:]
        for map in maps {
            for (period, value) in map where out[period] == nil {
                out[period] = value
            }
        }
        return out
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd StockCore && swift test --filter CompanyFactsParserTests`
Expected: PASS, 8 tests.

- [ ] **Step 6: Commit**

```bash
git add StockCore
git commit -m "feat(core): parse annual financials from EDGAR XBRL company facts"
```

---

### Task 9: Form 4 parser and EDGAR insider source

**Files:**
- Create: `StockCore/Sources/StockCore/EDGAR/MiniXML.swift`
- Create: `StockCore/Sources/StockCore/EDGAR/Form4Parser.swift`
- Create: `StockCore/Sources/StockCore/DataSources/InsiderSource.swift`
- Create: `StockCore/Tests/StockCoreTests/Fixtures/form4_purchase.xml`
- Create: `StockCore/Tests/StockCoreTests/Fixtures/form4_planned_sale.xml`
- Test: `StockCore/Tests/StockCoreTests/Form4Tests.swift`

**Interfaces:**
- Consumes: `InsiderTransaction` (Task 1), `EDGARClient`, `StockCoreError` (Task 6), `EDGARURL`, `EDGARSubmissions` (Task 7); test support `StubTransport`, `testEDGARClient` (Task 6).
- Produces:
  - `Form4Parser.transactions(from: Data) throws -> [InsiderTransaction]`
  - `protocol InsiderSource: Sendable { func insiderTransactions(cik: Int, since: String) async throws -> [InsiderTransaction] }`
  - `EDGARInsiderSource(client: EDGARClient, maxFilings: Int = 60)` (newest first; a filing that fails to download or parse is skipped)

- [ ] **Step 1: Add fixtures**

`StockCore/Tests/StockCoreTests/Fixtures/form4_purchase.xml`:

```xml
<?xml version="1.0"?>
<ownershipDocument>
    <schemaVersion>X0508</schemaVersion>
    <documentType>4</documentType>
    <periodOfReport>2026-08-12</periodOfReport>
    <aff10b5One>0</aff10b5One>
    <issuer>
        <issuerCik>0000123456</issuerCik>
        <issuerName>Sample Corp</issuerName>
        <issuerTradingSymbol>SMPL</issuerTradingSymbol>
    </issuer>
    <reportingOwner>
        <reportingOwnerId>
            <rptOwnerCik>0001234567</rptOwnerCik>
            <rptOwnerName>Doe Jane</rptOwnerName>
        </reportingOwnerId>
        <reportingOwnerRelationship>
            <isDirector>1</isDirector>
            <isOfficer>0</isOfficer>
        </reportingOwnerRelationship>
    </reportingOwner>
    <nonDerivativeTable>
        <nonDerivativeTransaction>
            <securityTitle><value>Common Stock</value></securityTitle>
            <transactionDate><value>2026-08-12</value></transactionDate>
            <transactionCoding>
                <transactionFormType>4</transactionFormType>
                <transactionCode>P</transactionCode>
                <equitySwapInvolved>0</equitySwapInvolved>
            </transactionCoding>
            <transactionAmounts>
                <transactionShares><value>1000</value></transactionShares>
                <transactionPricePerShare><value>50.25</value></transactionPricePerShare>
                <transactionAcquiredDisposedCode><value>A</value></transactionAcquiredDisposedCode>
            </transactionAmounts>
        </nonDerivativeTransaction>
    </nonDerivativeTable>
</ownershipDocument>
```

`StockCore/Tests/StockCoreTests/Fixtures/form4_planned_sale.xml`:

```xml
<?xml version="1.0"?>
<ownershipDocument>
    <schemaVersion>X0508</schemaVersion>
    <documentType>4</documentType>
    <periodOfReport>2026-06-01</periodOfReport>
    <aff10b5One>1</aff10b5One>
    <issuer>
        <issuerCik>0000123456</issuerCik>
        <issuerName>Sample Corp</issuerName>
        <issuerTradingSymbol>SMPL</issuerTradingSymbol>
    </issuer>
    <reportingOwner>
        <reportingOwnerId>
            <rptOwnerCik>0007654321</rptOwnerCik>
            <rptOwnerName>Roe Richard</rptOwnerName>
        </reportingOwnerId>
        <reportingOwnerRelationship>
            <isDirector>0</isDirector>
            <isOfficer>true</isOfficer>
            <officerTitle>Chief Financial Officer</officerTitle>
        </reportingOwnerRelationship>
    </reportingOwner>
    <nonDerivativeTable>
        <nonDerivativeTransaction>
            <securityTitle><value>Common Stock</value></securityTitle>
            <transactionDate><value>2026-06-01</value></transactionDate>
            <transactionCoding><transactionFormType>4</transactionFormType><transactionCode>M</transactionCode></transactionCoding>
            <transactionAmounts>
                <transactionShares><value>500</value></transactionShares>
                <transactionPricePerShare><value>20</value></transactionPricePerShare>
                <transactionAcquiredDisposedCode><value>A</value></transactionAcquiredDisposedCode>
            </transactionAmounts>
        </nonDerivativeTransaction>
        <nonDerivativeTransaction>
            <securityTitle><value>Common Stock</value></securityTitle>
            <transactionDate><value>2026-06-01-04:00</value></transactionDate>
            <transactionCoding><transactionFormType>4</transactionFormType><transactionCode>S</transactionCode></transactionCoding>
            <transactionAmounts>
                <transactionShares><value>500</value></transactionShares>
                <transactionPricePerShare><value>60</value></transactionPricePerShare>
                <transactionAcquiredDisposedCode><value>D</value></transactionAcquiredDisposedCode>
            </transactionAmounts>
        </nonDerivativeTransaction>
    </nonDerivativeTable>
</ownershipDocument>
```

- [ ] **Step 2: Write the failing tests**

`StockCore/Tests/StockCoreTests/Form4Tests.swift`:

```swift
import Foundation
import Testing
@testable import StockCore

@Suite struct Form4Tests {
    @Test func parsesAnOpenMarketPurchase() throws {
        let txs = try Form4Parser.transactions(from: Fixture.data("form4_purchase.xml"))
        #expect(txs.count == 1)
        let tx = try #require(txs.first)
        #expect(tx.ownerName == "Doe Jane")
        #expect(tx.ownerCik == 1234567)
        #expect(tx.isDirector && !tx.isOfficer)
        #expect(tx.officerTitle == nil)
        #expect(tx.date == "2026-08-12")
        #expect(tx.code == "P")
        #expect(tx.shares == 1000)
        #expect(tx.pricePerShare == 50.25)
        #expect(tx.value == 50_250)
        #expect(!tx.isPlanned10b51)
    }

    @Test func plannedSaleFlagsEveryRowAndTrimsTimezoneFromDates() throws {
        let txs = try Form4Parser.transactions(from: Fixture.data("form4_planned_sale.xml"))
        #expect(txs.map(\.code) == ["M", "S"])
        #expect(txs.allSatisfy(\.isPlanned10b51))
        #expect(txs.allSatisfy { $0.isOfficer && $0.officerTitle == "Chief Financial Officer" })
        #expect(txs[1].date == "2026-06-01")
    }

    @Test func footnoteMentioning10b51MarksThePlan() throws {
        let xml = """
        <ownershipDocument>
          <reportingOwner><reportingOwnerId><rptOwnerName>Old Style</rptOwnerName></reportingOwnerId></reportingOwner>
          <nonDerivativeTable><nonDerivativeTransaction>
            <transactionDate><value>2022-03-01</value></transactionDate>
            <transactionCoding><transactionCode>S</transactionCode></transactionCoding>
            <transactionAmounts><transactionShares><value>10</value></transactionShares>
              <transactionPricePerShare><value>5</value><footnoteId id="F1"/></transactionPricePerShare></transactionAmounts>
          </nonDerivativeTransaction></nonDerivativeTable>
          <footnotes><footnote id="F1">Sold under a Rule 10b5-1 trading plan adopted May 2021.</footnote></footnotes>
        </ownershipDocument>
        """
        let txs = try Form4Parser.transactions(from: Data(xml.utf8))
        #expect(txs.first?.isPlanned10b51 == true)
    }

    @Test func rowsMissingRequiredFieldsAreSkipped() throws {
        let xml = """
        <ownershipDocument>
          <reportingOwner><reportingOwnerId><rptOwnerName>X</rptOwnerName></reportingOwnerId></reportingOwner>
          <nonDerivativeTable><nonDerivativeTransaction>
            <transactionCoding><transactionCode>P</transactionCode></transactionCoding>
          </nonDerivativeTransaction></nonDerivativeTable>
        </ownershipDocument>
        """
        #expect(try Form4Parser.transactions(from: Data(xml.utf8)).isEmpty)
    }

    @Test func malformedOrWrongDocumentsThrow() {
        #expect(throws: StockCoreError.self) {
            try Form4Parser.transactions(from: Data("<ownershipDocument><broken".utf8))
        }
        #expect(throws: StockCoreError.self) {
            try Form4Parser.transactions(from: Data("<html><body>hi</body></html>".utf8))
        }
    }

    @Test func insiderSourceFetchesRecentForm4sAndSkipsBadOnes() async throws {
        let stub = StubTransport()
        stub.respond(EDGARURL.submissions(cik: 123456).absoluteString,
                     body: try Fixture.data("submissions_sample.json"))
        let aug = EDGARURL.filingDocument(cik: 123456, accession: "0000123456-26-000050",
                                          primaryDocument: "xslF345X05/form4-aug.xml")
        let jun = EDGARURL.filingDocument(cik: 123456, accession: "0000123456-26-000030",
                                          primaryDocument: "xslF345X05/form4-jun.xml")
        let old = EDGARURL.filingDocument(cik: 123456, accession: "0000123456-25-000010",
                                          primaryDocument: "xslF345X05/form4-old.xml")
        stub.respond(aug.absoluteString, body: try Fixture.data("form4_purchase.xml"))
        stub.respond(jun.absoluteString, body: Data("<ownershipDocument><broken".utf8))

        let source = EDGARInsiderSource(client: testEDGARClient(stub))
        let txs = try await source.insiderTransactions(cik: 123456, since: "2026-03-31")

        #expect(txs.map(\.ownerName) == ["Doe Jane"])
        #expect(stub.requestedURLs.contains(jun.absoluteString))
        #expect(!stub.requestedURLs.contains(old.absoluteString))
    }

    @Test func insiderSourceRespectsMaxFilings() async throws {
        let stub = StubTransport()
        stub.respond(EDGARURL.submissions(cik: 123456).absoluteString,
                     body: try Fixture.data("submissions_sample.json"))
        let source = EDGARInsiderSource(client: testEDGARClient(stub), maxFilings: 1)
        _ = try await source.insiderTransactions(cik: 123456, since: "2026-03-31")
        #expect(stub.requestedURLs.count == 2)  // submissions + one Form 4
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd StockCore && swift test --filter Form4Tests`
Expected: build FAILS with `cannot find 'Form4Parser' in scope`.

- [ ] **Step 4: Implement MiniXML**

`StockCore/Sources/StockCore/EDGAR/MiniXML.swift`:

```swift
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Minimal element tree — enough to read SEC ownership XML without a dependency.
final class XMLElementNode {
    let name: String
    var text = ""
    var children: [XMLElementNode] = []

    init(name: String) { self.name = name }

    func first(_ name: String) -> XMLElementNode? { children.first { $0.name == name } }
    func all(_ name: String) -> [XMLElementNode] { children.filter { $0.name == name } }

    func node(_ path: [String]) -> XMLElementNode? {
        path.reduce(Optional(self)) { $0?.first($1) }
    }

    /// Trimmed text at a child path, nil when missing or empty.
    func string(_ path: String...) -> String? {
        guard let text = node(path)?.text.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    /// SEC booleans are written "1"/"0" or "true"/"false".
    func flag(_ path: String...) -> Bool {
        let value = node(path)?.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "1" || value == "true"
    }
}

final class MiniXMLParser: NSObject, XMLParserDelegate {
    private var stack: [XMLElementNode] = []
    private var root: XMLElementNode?

    static func parse(_ data: Data) throws -> XMLElementNode {
        let delegate = MiniXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else {
            throw StockCoreError.malformed("XML: \(parser.parserError.map { "\($0)" } ?? "no root element")")
        }
        return root
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let node = XMLElementNode(name: elementName)
        if let parent = stack.last {
            parent.children.append(node)
        } else {
            root = node
        }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        _ = stack.popLast()
    }
}
```

- [ ] **Step 5: Implement Form4Parser**

`StockCore/Sources/StockCore/EDGAR/Form4Parser.swift`:

```swift
import Foundation

/// SEC Form 4 ownership XML → non-derivative transactions.
public enum Form4Parser {
    public static func transactions(from data: Data) throws -> [InsiderTransaction] {
        let root = try MiniXMLParser.parse(data)
        guard root.name == "ownershipDocument" else {
            throw StockCoreError.malformed("Expected ownershipDocument, found \(root.name)")
        }

        let owner = root.first("reportingOwner")
        let ownerName = owner?.string("reportingOwnerId", "rptOwnerName") ?? "Unknown"
        let ownerCik = owner?.string("reportingOwnerId", "rptOwnerCik").flatMap { Int($0) }
        let isOfficer = owner?.flag("reportingOwnerRelationship", "isOfficer") ?? false
        let isDirector = owner?.flag("reportingOwnerRelationship", "isDirector") ?? false
        let officerTitle = owner?.string("reportingOwnerRelationship", "officerTitle")

        // Filings since April 2023 have an explicit checkbox; older ones say so in a footnote.
        let footnotes = root.first("footnotes")?.all("footnote").map(\.text).joined(separator: " ") ?? ""
        let planned = root.flag("aff10b5One")
            || footnotes.range(of: "10b5-1", options: .caseInsensitive) != nil

        let rows = root.first("nonDerivativeTable")?.all("nonDerivativeTransaction") ?? []
        return rows.compactMap { row in
            guard let date = row.string("transactionDate", "value"),
                  let code = row.string("transactionCoding", "transactionCode"),
                  let shares = row.string("transactionAmounts", "transactionShares", "value").flatMap({ Double($0) })
            else { return nil }
            let price = row.string("transactionAmounts", "transactionPricePerShare", "value").flatMap { Double($0) }
            return InsiderTransaction(ownerName: ownerName, ownerCik: ownerCik, isOfficer: isOfficer,
                                      isDirector: isDirector, officerTitle: officerTitle,
                                      date: String(date.prefix(10)), code: code, shares: shares,
                                      pricePerShare: price, isPlanned10b51: planned)
        }
    }
}
```

- [ ] **Step 6: Implement the insider source**

`StockCore/Sources/StockCore/DataSources/InsiderSource.swift`:

```swift
import Foundation

public protocol InsiderSource: Sendable {
    /// Transactions dated on or after `since` ("yyyy-MM-dd"), newest first.
    func insiderTransactions(cik: Int, since: String) async throws -> [InsiderTransaction]
}

public struct EDGARInsiderSource: InsiderSource {
    let client: EDGARClient
    let maxFilings: Int

    public init(client: EDGARClient, maxFilings: Int = 60) {
        self.client = client
        self.maxFilings = maxFilings
    }

    public func insiderTransactions(cik: Int, since: String) async throws -> [InsiderTransaction] {
        let submissions = try EDGARSubmissions(jsonData: try await client.get(EDGARURL.submissions(cik: cik)))
        let filings = submissions.recentFilings
            .filter { $0.form == "4" && $0.filingDate >= since }
            .prefix(maxFilings)

        var result: [InsiderTransaction] = []
        for filing in filings {
            let url = EDGARURL.filingDocument(cik: cik, accession: filing.accessionNumber,
                                              primaryDocument: filing.primaryDocument)
            // One unreadable filing must not hide the rest.
            guard let data = try? await client.get(url),
                  let transactions = try? Form4Parser.transactions(from: data) else { continue }
            result += transactions.filter { $0.date >= since }
        }
        return result.sorted { $0.date > $1.date }
    }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd StockCore && swift test --filter Form4Tests`
Expected: PASS, 7 tests.

- [ ] **Step 8: Commit**

```bash
git add StockCore
git commit -m "feat(core): parse Form 4 filings and fetch recent insider trades"
```

---

### Task 10: Fundamentals, price and holdings sources

**Files:**
- Create: `StockCore/Sources/StockCore/DataSources/FundamentalsSource.swift`
- Create: `StockCore/Sources/StockCore/DataSources/PriceSource.swift`
- Create: `StockCore/Sources/StockCore/DataSources/HoldingsSource.swift`
- Create: `StockCore/Tests/StockCoreTests/Fixtures/finnhub_quote.json`
- Create: `StockCore/Tests/StockCoreTests/Fixtures/finnhub_metric.json`
- Test: `StockCore/Tests/StockCoreTests/DataSourceTests.swift`

**Interfaces:**
- Consumes: models (Task 1), `HTTPTransport`, `HTTPResponse`, `RateLimiter`, `EDGARClient`, `StockCoreError` (Task 6), `EDGARURL`, `CompanyDirectory`, `DirectoryEntry`, `EDGARSubmissions` (Task 7), `CompanyFactsParser` (Task 8); test support `StubTransport`, `testEDGARClient`, `Fixture`.
- Produces:
  - `FundamentalsBundle(company: Company, financials: [AnnualFinancials])`
  - `protocol FundamentalsSource: Sendable { func fundamentals(for entry: DirectoryEntry) async throws -> FundamentalsBundle }`; `EDGARFundamentalsSource(client: EDGARClient)`
  - `protocol PriceSource: Sendable { func quote(ticker: String) async throws -> PriceQuote }`; `FinnhubPriceSource(apiKey: String, transport: any HTTPTransport = URLSessionTransport(), limiter: RateLimiter = RateLimiter(requestsPerSecond: 55.0 / 60.0))`; `static finnhubSymbol(_:) -> String`
  - `HoldingsFile(schemaVersion: Int, ticker: String, quarters: [InstitutionalQuarter])`
  - `protocol HoldingsSource: Sendable { func holdings(ticker: String) async throws -> [InstitutionalQuarter] }`; `PublishedHoldingsSource(baseURL: URL, transport: any HTTPTransport = URLSessionTransport())` (404 → `[]`)

- [ ] **Step 1: Add fixtures**

`StockCore/Tests/StockCoreTests/Fixtures/finnhub_quote.json`:

```json
{"c": 142.3, "d": 1.2, "dp": 0.85, "h": 143.0, "l": 140.1, "o": 141.0, "pc": 141.1, "t": 1790798400}
```

(`1790798400` is 2026-09-30 UTC.)

`StockCore/Tests/StockCoreTests/Fixtures/finnhub_metric.json` — real responses mix numbers, nulls and date strings:

```json
{
  "metric": {
    "52WeekHigh": 150.2,
    "52WeekHighDate": "2026-07-14",
    "peTTM": null,
    "peExclExtraTTM": 38.4,
    "peBasicExclExtraTTM": 39.1,
    "epsGrowth3Y": 28.5
  },
  "metricType": "all",
  "symbol": "NOVA"
}
```

- [ ] **Step 2: Write the failing tests**

`StockCore/Tests/StockCoreTests/DataSourceTests.swift`:

```swift
import Foundation
import Testing
@testable import StockCore

@Suite struct DataSourceTests {
    // MARK: Fundamentals

    @Test func edgarFundamentalsCombineSubmissionsAndFacts() async throws {
        let stub = StubTransport()
        stub.respond(EDGARURL.submissions(cik: 123456).absoluteString,
                     body: try Fixture.data("submissions_sample.json"))
        stub.respond(EDGARURL.companyFacts(cik: 123456).absoluteString,
                     body: try Fixture.data("companyfacts_sample.json"))
        let source = EDGARFundamentalsSource(client: testEDGARClient(stub))
        let bundle = try await source.fundamentals(for: DirectoryEntry(ticker: "SMPL", cik: 123456, name: "Sample Corp"))
        #expect(bundle.company == Company(ticker: "SMPL", cik: 123456, name: "Sample Corp",
                                          sicCode: 3674, sector: "Semiconductors & Related Devices"))
        #expect(bundle.financials.count == 5)
        #expect(bundle.financials.last?.revenue == 190)
    }

    // MARK: Finnhub

    func finnhub(_ stub: StubTransport) -> FinnhubPriceSource {
        FinnhubPriceSource(apiKey: "KEY", transport: stub, limiter: RateLimiter(requestsPerSecond: 1_000))
    }
    func quoteURL(_ symbol: String) -> String { "https://finnhub.io/api/v1/quote?symbol=\(symbol)&token=KEY" }
    func metricURL(_ symbol: String) -> String {
        "https://finnhub.io/api/v1/stock/metric?symbol=\(symbol)&metric=all&token=KEY"
    }

    @Test func quoteCombinesPriceAndFirstAvailablePE() async throws {
        let stub = StubTransport()
        stub.respond(quoteURL("NOVA"), body: try Fixture.data("finnhub_quote.json"))
        stub.respond(metricURL("NOVA"), body: try Fixture.data("finnhub_metric.json"))
        let quote = try await finnhub(stub).quote(ticker: "nova")
        #expect(quote == PriceQuote(price: 142.3, peTTM: 38.4, asOf: "2026-09-30"))
    }

    @Test func classShareTickerUsesDotSymbol() async throws {
        #expect(FinnhubPriceSource.finnhubSymbol("BRK-B") == "BRK.B")
        #expect(FinnhubPriceSource.finnhubSymbol("brk.b") == "BRK.B")
        let stub = StubTransport()
        stub.respond(quoteURL("BRK.B"), body: try Fixture.data("finnhub_quote.json"))
        _ = try await finnhub(stub).quote(ticker: "BRK-B")
        #expect(stub.requestedURLs.first == quoteURL("BRK.B"))
    }

    @Test func zeroQuoteIsTreatedAsMissing() async {
        let stub = StubTransport()
        stub.respond(quoteURL("GONE"), body: Data(#"{"c":0,"d":null,"dp":null,"h":0,"l":0,"o":0,"pc":0,"t":0}"#.utf8))
        await #expect(throws: StockCoreError.missingData("No price for GONE")) {
            try await finnhub(stub).quote(ticker: "GONE")
        }
    }

    @Test func missingMetricsStillReturnAPrice() async throws {
        let stub = StubTransport()
        stub.respond(quoteURL("NOVA"), body: try Fixture.data("finnhub_quote.json"))
        let quote = try await finnhub(stub).quote(ticker: "NOVA")
        #expect(quote.price == 142.3)
        #expect(quote.peTTM == nil)
    }

    @Test func httpErrorsNeverLeakTheAPIKey() async {
        let stub = StubTransport()
        stub.respond(quoteURL("NOVA"), statuses: [429])
        do {
            _ = try await finnhub(stub).quote(ticker: "NOVA")
            Issue.record("Expected an error")
        } catch let StockCoreError.http(status, url) {
            #expect(status == 429)
            #expect(!url.contains("KEY"))
            #expect(url.contains("symbol=NOVA"))
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    // MARK: Holdings

    @Test func holdingsAreDecodedAndSorted() async throws {
        let file = HoldingsFile(schemaVersion: 1, ticker: "NOVA", quarters: [
            InstitutionalQuarter(period: "2026-06-30", totalShares: 1100, holderCount: 50),
            InstitutionalQuarter(period: "2026-03-31", totalShares: 1000, holderCount: 40),
        ])
        let stub = StubTransport()
        stub.respond("https://example.test/data/holdings/NOVA.json", body: try JSONEncoder().encode(file))
        let source = PublishedHoldingsSource(baseURL: URL(string: "https://example.test/data")!, transport: stub)
        let quarters = try await source.holdings(ticker: "NOVA")
        #expect(quarters.map(\.period) == ["2026-03-31", "2026-06-30"])
    }

    @Test func holdingsPathUsesNormalizedTicker() async throws {
        let stub = StubTransport()
        let source = PublishedHoldingsSource(baseURL: URL(string: "https://example.test/data")!, transport: stub)
        _ = try await source.holdings(ticker: "brk.b")
        #expect(stub.requestedURLs == ["https://example.test/data/holdings/BRK-B.json"])
    }

    @Test func missingHoldingsFileMeansNoData() async throws {
        let source = PublishedHoldingsSource(baseURL: URL(string: "https://example.test/data")!,
                                             transport: StubTransport())
        #expect(try await source.holdings(ticker: "NOVA").isEmpty)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd StockCore && swift test --filter DataSourceTests`
Expected: build FAILS with `cannot find 'EDGARFundamentalsSource' in scope`.

- [ ] **Step 4: Implement the fundamentals source**

`StockCore/Sources/StockCore/DataSources/FundamentalsSource.swift`:

```swift
import Foundation

public struct FundamentalsBundle: Codable, Hashable, Sendable {
    public var company: Company
    public var financials: [AnnualFinancials]

    public init(company: Company, financials: [AnnualFinancials]) {
        self.company = company
        self.financials = financials
    }
}

public protocol FundamentalsSource: Sendable {
    func fundamentals(for entry: DirectoryEntry) async throws -> FundamentalsBundle
}

public struct EDGARFundamentalsSource: FundamentalsSource {
    let client: EDGARClient

    public init(client: EDGARClient) {
        self.client = client
    }

    public func fundamentals(for entry: DirectoryEntry) async throws -> FundamentalsBundle {
        async let submissionsData = client.get(EDGARURL.submissions(cik: entry.cik))
        async let factsData = client.get(EDGARURL.companyFacts(cik: entry.cik))
        let submissions = try EDGARSubmissions(jsonData: try await submissionsData)
        let financials = try CompanyFactsParser.annualFinancials(from: try await factsData)
        let company = Company(ticker: entry.ticker, cik: entry.cik, name: entry.name,
                              sicCode: submissions.sicCode, sector: submissions.sicDescription)
        return FundamentalsBundle(company: company, financials: financials)
    }
}
```

- [ ] **Step 5: Implement the Finnhub price source**

`StockCore/Sources/StockCore/DataSources/PriceSource.swift`:

```swift
import Foundation

public protocol PriceSource: Sendable {
    func quote(ticker: String) async throws -> PriceQuote
}

/// Finnhub free tier: 60 calls/minute, personal use. Two calls per quote.
public struct FinnhubPriceSource: PriceSource {
    public static let baseURL = URL(string: "https://finnhub.io/api/v1")!
    static let peKeys = ["peTTM", "peExclExtraTTM", "peBasicExclExtraTTM"]

    let apiKey: String
    let transport: any HTTPTransport
    let limiter: RateLimiter

    public init(apiKey: String,
                transport: any HTTPTransport = URLSessionTransport(),
                limiter: RateLimiter = RateLimiter(requestsPerSecond: 55.0 / 60.0)) {
        self.apiKey = apiKey
        self.transport = transport
        self.limiter = limiter
    }

    /// Finnhub writes class shares with a dot ("BRK.B"); EDGAR uses a dash.
    public static func finnhubSymbol(_ ticker: String) -> String {
        CompanyDirectory.normalize(ticker).replacingOccurrences(of: "-", with: ".")
    }

    private struct QuoteDTO: Decodable {
        let c: Double
        let t: Double?
    }

    /// Finnhub metric values are mostly numbers but include nulls and date strings.
    private struct LenientDouble: Decodable {
        let value: Double?
        init(from decoder: Decoder) throws {
            value = try? decoder.singleValueContainer().decode(Double.self)
        }
    }

    private struct MetricDTO: Decodable {
        let metric: [String: LenientDouble]
    }

    public func quote(ticker: String) async throws -> PriceQuote {
        let symbol = Self.finnhubSymbol(ticker)
        let quote: QuoteDTO = try await fetch(url("quote", [URLQueryItem(name: "symbol", value: symbol)]))
        // Unknown and delisted symbols come back as all zeros rather than an error.
        guard quote.c > 0, let timestamp = quote.t, timestamp > 0 else {
            throw StockCoreError.missingData("No price for \(symbol)")
        }
        let metrics: MetricDTO? = try? await fetch(url("stock/metric", [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "metric", value: "all"),
        ]))
        let pe = Self.peKeys.lazy.compactMap { metrics?.metric[$0]?.value }.first
        return PriceQuote(price: quote.c, peTTM: pe,
                          asOf: ISODay.string(Date(timeIntervalSince1970: timestamp)))
    }

    private func url(_ path: String, _ items: [URLQueryItem]) -> URL {
        let endpoint = path.split(separator: "/").reduce(Self.baseURL) {
            $0.appendingPathComponent(String($1))
        }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = items + [URLQueryItem(name: "token", value: apiKey)]
        return components.url!
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        await limiter.acquire()
        let response = try await transport.get(url, headers: [:])
        guard (200..<300).contains(response.status) else {
            throw StockCoreError.http(status: response.status, url: Self.redacted(url))
        }
        do {
            return try JSONDecoder().decode(T.self, from: response.body)
        } catch {
            throw StockCoreError.malformed("Finnhub \(url.path): \(error)")
        }
    }

    static func redacted(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.path }
        components.queryItems = components.queryItems?.filter { $0.name != "token" }
        return components.string ?? url.path
    }
}
```

- [ ] **Step 6: Implement the holdings source**

`StockCore/Sources/StockCore/DataSources/HoldingsSource.swift`:

```swift
import Foundation

/// holdings/{TICKER}.json as published by the pipeline (Plan 2).
public struct HoldingsFile: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var ticker: String
    public var quarters: [InstitutionalQuarter]

    public init(schemaVersion: Int, ticker: String, quarters: [InstitutionalQuarter]) {
        self.schemaVersion = schemaVersion
        self.ticker = ticker
        self.quarters = quarters
    }
}

public protocol HoldingsSource: Sendable {
    /// Oldest → newest; empty when no 13F data exists for the ticker.
    func holdings(ticker: String) async throws -> [InstitutionalQuarter]
}

public struct PublishedHoldingsSource: HoldingsSource {
    let baseURL: URL
    let transport: any HTTPTransport

    public init(baseURL: URL, transport: any HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.transport = transport
    }

    public func holdings(ticker: String) async throws -> [InstitutionalQuarter] {
        let url = baseURL
            .appendingPathComponent("holdings")
            .appendingPathComponent("\(CompanyDirectory.normalize(ticker)).json")
        let response = try await transport.get(url, headers: [:])
        if response.status == 404 { return [] }
        guard (200..<300).contains(response.status) else {
            throw StockCoreError.http(status: response.status, url: url.absoluteString)
        }
        do {
            return try JSONDecoder().decode(HoldingsFile.self, from: response.body)
                .quarters.sorted { $0.period < $1.period }
        } catch {
            throw StockCoreError.malformed("holdings \(ticker): \(error)")
        }
    }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd StockCore && swift test --filter DataSourceTests`
Expected: PASS, 9 tests.

- [ ] **Step 8: Commit**

```bash
git add StockCore
git commit -m "feat(core): add EDGAR fundamentals, Finnhub price and published holdings sources"
```

---

### Task 11: StockReport and StockAnalyzer

**Files:**
- Create: `StockCore/Sources/StockCore/StockReport.swift`
- Create: `StockCore/Sources/StockCore/StockAnalyzer.swift`
- Test: `StockCore/Tests/StockCoreTests/StockAnalyzerTests.swift`
- Modify: `README.md` (append a StockCore section)

**Interfaces:**
- Consumes: everything above — `CompanyInputs`, `MetricCalculator`, `PercentileTable`, `ScoringEngine`, `UpsideCalculator`, `FundamentalsSource`, `PriceSource`, `InsiderSource`, `HoldingsSource`, `DirectoryEntry`, `ISODay`.
- Produces (used by Plans 2 and 3):
  - `struct StockReport` with `schemaVersion`, `company`, `quote`, `financials`, `insiderTransactions`, `holdings`, `metrics`, `score`, `upside`, `generatedAt`; `static let currentSchemaVersion = 1`
  - `StockAnalyzer(fundamentals: any FundamentalsSource, prices: (any PriceSource)?, insiders: any InsiderSource, holdings: any HoldingsSource)`
  - `func gatherInputs(for entry: DirectoryEntry, asOf: String) async throws -> CompanyInputs` (only fundamentals failures throw; price → nil, insiders → nil, holdings → [])
  - `static func report(inputs: CompanyInputs, metrics: CompanyMetrics? = nil, table: PercentileTable, sectorMedianPE: Double?, generatedAt: String, engine: ScoringEngine = ScoringEngine()) -> StockReport`

- [ ] **Step 1: Write the failing tests**

`StockCore/Tests/StockCoreTests/StockAnalyzerTests.swift`:

```swift
import Foundation
import Testing
@testable import StockCore

private struct Failure: Error {}

private struct FakeFundamentals: FundamentalsSource {
    var fail = false
    func fundamentals(for entry: DirectoryEntry) async throws -> FundamentalsBundle {
        if fail { throw Failure() }
        return FundamentalsBundle(
            company: Company(ticker: entry.ticker, cik: entry.cik, name: entry.name, sicCode: 3674),
            financials: [
                year("2021-12-31", revenue: 100, eps: 1.0, opIncome: 10, netIncome: 8, ocf: 12, capex: 2),
                year("2022-12-31", revenue: 120, eps: 1.2, opIncome: 13, netIncome: 10, ocf: 14, capex: 2),
                year("2023-12-31", revenue: 145, eps: 1.5, opIncome: 17, netIncome: 13, ocf: 18, capex: 3),
                year("2024-12-31", revenue: 175, eps: 1.9, opIncome: 23, netIncome: 17, ocf: 24, capex: 4,
                     debt: 20, cash: 10),
            ])
    }
}

private struct FakePrices: PriceSource {
    var fail = false
    func quote(ticker: String) async throws -> PriceQuote {
        if fail { throw Failure() }
        return PriceQuote(price: 57, peTTM: 30, asOf: "2026-09-30")
    }
}

private struct FakeInsiders: InsiderSource {
    var fail = false
    func insiderTransactions(cik: Int, since: String) async throws -> [InsiderTransaction] {
        if fail { throw Failure() }
        #expect(since == "2026-04-01")
        return [insider("A", "P", "2026-08-01", shares: 100, price: 50)]
    }
}

private struct FakeHoldings: HoldingsSource {
    var fail = false
    func holdings(ticker: String) async throws -> [InstitutionalQuarter] {
        if fail { throw Failure() }
        return [InstitutionalQuarter(period: "2026-03-31", totalShares: 1000, holderCount: 40),
                InstitutionalQuarter(period: "2026-06-30", totalShares: 1100, holderCount: 44)]
    }
}

@Suite struct StockAnalyzerTests {
    let entry = DirectoryEntry(ticker: "NOVA", cik: 123456, name: "Novatek")

    func analyzer(fundamentals: Bool = true, prices: Bool = true, insiders: Bool = true,
                  holdings: Bool = true, noPriceSource: Bool = false) -> StockAnalyzer {
        StockAnalyzer(fundamentals: FakeFundamentals(fail: !fundamentals),
                      prices: noPriceSource ? nil : FakePrices(fail: !prices),
                      insiders: FakeInsiders(fail: !insiders),
                      holdings: FakeHoldings(fail: !holdings))
    }

    @Test func gathersEverySource() async throws {
        let inputs = try await analyzer().gatherInputs(for: entry, asOf: "2026-09-30")
        #expect(inputs.company.sicCode == 3674)
        #expect(inputs.financials.count == 4)
        #expect(inputs.quote?.price == 57)
        #expect(inputs.insiderTransactions?.count == 1)
        #expect(inputs.holdings.count == 2)
        #expect(inputs.asOf == "2026-09-30")
    }

    @Test func optionalSourcesDegradeInsteadOfFailing() async throws {
        let inputs = try await analyzer(prices: false, insiders: false, holdings: false)
            .gatherInputs(for: entry, asOf: "2026-09-30")
        #expect(inputs.quote == nil)
        #expect(inputs.insiderTransactions == nil)
        #expect(inputs.holdings.isEmpty)
        #expect(inputs.financials.count == 4)
    }

    @Test func noPriceSourceMeansNoQuote() async throws {
        let inputs = try await analyzer(noPriceSource: true).gatherInputs(for: entry, asOf: "2026-09-30")
        #expect(inputs.quote == nil)
    }

    @Test func fundamentalsFailureThrows() async {
        await #expect(throws: Failure.self) {
            try await analyzer(fundamentals: false).gatherInputs(for: entry, asOf: "2026-09-30")
        }
    }

    @Test func reportScoresAndProjects() async throws {
        let inputs = try await analyzer().gatherInputs(for: entry, asOf: "2026-09-30")
        let report = StockAnalyzer.report(inputs: inputs, table: .identity, sectorMedianPE: 25,
                                          generatedAt: "2026-09-30T22:45:00Z")
        #expect(report.schemaVersion == StockReport.currentSchemaVersion)
        #expect(report.company.ticker == "NOVA")
        #expect(report.score.total != nil)
        #expect(report.score.parts.count == 4)
        #expect(report.upside.ifGrowthContinues != nil)
        #expect(report.upside.ifPEMovesToSectorMedian?.assumedPE == 25)
        #expect(report.metrics[.insiderNetBuying] == 5000)
        #expect(report.generatedAt == "2026-09-30T22:45:00Z")
    }

    @Test func reportWithoutPriceExplainsMissingUpside() async throws {
        let inputs = try await analyzer(prices: false).gatherInputs(for: entry, asOf: "2026-09-30")
        let report = StockAnalyzer.report(inputs: inputs, table: .identity, sectorMedianPE: 25,
                                          generatedAt: "2026-09-30T22:45:00Z")
        #expect(report.upside.unavailableReason == "No current price is available.")
        #expect(report.score.parts[.valuation] == nil)
        #expect(report.score.total != nil)
    }

    @Test func reportUsesPrecomputedMetricsWhenGiven() async throws {
        let inputs = try await analyzer().gatherInputs(for: entry, asOf: "2026-09-30")
        let custom = CompanyMetrics(values: [.revenueCAGR3Y: 99])
        let report = StockAnalyzer.report(inputs: inputs, metrics: custom, table: .identity,
                                          sectorMedianPE: nil, generatedAt: "x")
        #expect(report.metrics == custom)
        #expect(report.score.parts.keys.map(\.rawValue) == ["growth"])
    }

    @Test func reportRoundTripsThroughJSON() async throws {
        let inputs = try await analyzer().gatherInputs(for: entry, asOf: "2026-09-30")
        let report = StockAnalyzer.report(inputs: inputs, table: .identity, sectorMedianPE: 25,
                                          generatedAt: "2026-09-30T22:45:00Z")
        let data = try JSONEncoder().encode(report)
        #expect(try JSONDecoder().decode(StockReport.self, from: data) == report)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd StockCore && swift test --filter StockAnalyzerTests`
Expected: build FAILS with `cannot find 'StockAnalyzer' in scope`.

- [ ] **Step 3: Implement StockReport**

`StockCore/Sources/StockCore/StockReport.swift`:

```swift
/// Everything the report screen shows for one stock. Published as reports/{TICKER}.json.
public struct StockReport: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var company: Company
    public var quote: PriceQuote?
    public var financials: [AnnualFinancials]
    public var insiderTransactions: [InsiderTransaction]?
    public var holdings: [InstitutionalQuarter]
    public var metrics: CompanyMetrics
    public var score: ScoreBreakdown
    public var upside: UpsideResult
    /// ISO 8601 timestamp.
    public var generatedAt: String

    public init(schemaVersion: Int = StockReport.currentSchemaVersion, company: Company,
                quote: PriceQuote?, financials: [AnnualFinancials],
                insiderTransactions: [InsiderTransaction]?, holdings: [InstitutionalQuarter],
                metrics: CompanyMetrics, score: ScoreBreakdown, upside: UpsideResult,
                generatedAt: String) {
        self.schemaVersion = schemaVersion
        self.company = company
        self.quote = quote
        self.financials = financials
        self.insiderTransactions = insiderTransactions
        self.holdings = holdings
        self.metrics = metrics
        self.score = score
        self.upside = upside
        self.generatedAt = generatedAt
    }
}
```

- [ ] **Step 4: Implement StockAnalyzer**

`StockCore/Sources/StockCore/StockAnalyzer.swift`:

```swift
/// Gathers data for one company and turns it into a report.
///
/// Pipeline: gatherInputs for every S&P 500 company → MetricCalculator → PercentileTable.build
/// → report(…) for each. App (watchlist): gatherInputs → report(…, table: downloaded table).
public struct StockAnalyzer: Sendable {
    let fundamentals: any FundamentalsSource
    let prices: (any PriceSource)?
    let insiders: any InsiderSource
    let holdings: any HoldingsSource

    public init(fundamentals: any FundamentalsSource, prices: (any PriceSource)?,
                insiders: any InsiderSource, holdings: any HoldingsSource) {
        self.fundamentals = fundamentals
        self.prices = prices
        self.insiders = insiders
        self.holdings = holdings
    }

    /// Only a fundamentals failure throws; every other source degrades to "no data".
    public func gatherInputs(for entry: DirectoryEntry, asOf: String) async throws -> CompanyInputs {
        let since = ISODay.adding(days: -MetricCalculator.insiderWindowDays, to: asOf) ?? asOf
        async let bundle = fundamentals.fundamentals(for: entry)
        async let quote = fetchQuote(entry.ticker)
        async let insiderTransactions = fetchInsiders(cik: entry.cik, since: since)
        async let quarters = fetchHoldings(entry.ticker)

        let fundamentalsBundle = try await bundle
        return CompanyInputs(company: fundamentalsBundle.company,
                             financials: fundamentalsBundle.financials,
                             quote: await quote,
                             insiderTransactions: await insiderTransactions,
                             holdings: await quarters,
                             asOf: asOf)
    }

    public static func report(inputs: CompanyInputs, metrics: CompanyMetrics? = nil,
                              table: PercentileTable, sectorMedianPE: Double?, generatedAt: String,
                              engine: ScoringEngine = ScoringEngine()) -> StockReport {
        let resolvedMetrics = metrics ?? MetricCalculator.metrics(for: inputs)
        let score = engine.score(company: inputs.company, metrics: resolvedMetrics, table: table)
        let upside = UpsideCalculator.calculate(price: inputs.quote?.price, peTTM: inputs.quote?.peTTM,
                                                epsCAGR: resolvedMetrics.strictEPSCAGR3Y,
                                                sectorMedianPE: sectorMedianPE)
        return StockReport(company: inputs.company, quote: inputs.quote, financials: inputs.financials,
                           insiderTransactions: inputs.insiderTransactions, holdings: inputs.holdings,
                           metrics: resolvedMetrics, score: score, upside: upside,
                           generatedAt: generatedAt)
    }

    private func fetchQuote(_ ticker: String) async -> PriceQuote? {
        guard let prices else { return nil }
        return try? await prices.quote(ticker: ticker)
    }

    private func fetchInsiders(cik: Int, since: String) async -> [InsiderTransaction]? {
        try? await insiders.insiderTransactions(cik: cik, since: since)
    }

    private func fetchHoldings(_ ticker: String) async -> [InstitutionalQuarter] {
        (try? await holdings.holdings(ticker: ticker)) ?? []
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd StockCore && swift test --filter StockAnalyzerTests`
Expected: PASS, 8 tests.

- [ ] **Step 6: Run the whole suite**

Run: `cd StockCore && swift test`
Expected: PASS, all 85 tests, no warnings about Sendable or concurrency.

- [ ] **Step 7: Document StockCore in the README**

Append to `README.md`:

````markdown

## StockCore

Swift package with the data, scoring and upside logic shared by the nightly
pipeline and the iOS app. No UI, no third-party dependencies; builds on macOS,
iOS and Linux.

```bash
cd StockCore
swift test
```

Design: [docs/superpowers/specs/2026-10-01-stock-picker-design.md](docs/superpowers/specs/2026-10-01-stock-picker-design.md)
````

- [ ] **Step 8: Commit**

```bash
git add README.md StockCore
git commit -m "feat(core): add StockAnalyzer and StockReport tying sources to scoring"
```

---

## After this plan

- Push and confirm the **StockCore tests** GitHub Action passes on Linux.
- Next: write Plan 2 (Pipeline) against the real `StockCore` API: S&P 500 list, 13F download and CUSIP mapping, Form 4 caching by accession number (immutable, so each filing is fetched once ever), nightly scoring, JSON publishing to GitHub Pages.
- Then Plan 3 (StockApp).
