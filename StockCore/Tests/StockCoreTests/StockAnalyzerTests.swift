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
