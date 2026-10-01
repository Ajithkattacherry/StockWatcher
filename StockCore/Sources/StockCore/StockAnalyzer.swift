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
