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
