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

        var negative = fourYears
        negative[3].capitalExpenditure = 40  // FCF = -10
        let n = MetricCalculator.metrics(for: inputs(financials: negative))
        #expect(n[.netDebtToFCF] == nil)
        #expect(approx(n[.freeCashFlowMargin], -10 / 133.1))
    }

    @Test func allMetricValuesAreFinite() {
        let weird = [
            year("2021-12-31", revenue: 0, eps: 0, opIncome: 0),
            year("2022-12-31", revenue: -5, eps: -1, opIncome: -3),
            year("2023-12-31", revenue: 0, eps: 0, opIncome: 0),
            year("2024-12-31", revenue: 0, eps: -2, opIncome: -1, netIncome: -4, ocf: -1, capex: 2, debt: 10),
        ]
        // An absurdly large trade (overflow, not a per-field guard) exercises the
        // final isFinite filter rather than one of the upstream nil-guards.
        let overflow = insider("Big", "P", "2026-08-01", shares: .greatestFiniteMagnitude, price: 2)
        let m = MetricCalculator.metrics(for: inputs(
            financials: weird, quote: PriceQuote(price: 5, peTTM: -3, asOf: "2026-09-30"),
            insiders: [overflow],
            holdings: [InstitutionalQuarter(period: "2026-03-31", totalShares: 0, holderCount: 0),
                       InstitutionalQuarter(period: "2026-06-30", totalShares: 10, holderCount: 2)]))
        #expect(m.values.values.allSatisfy { $0.isFinite })
        #expect(m[.insiderNetBuying] == nil)
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
        #expect(m[.insiderNetBuying] == 1000.0 + 500.0 + 100.0 - 200.0)
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
