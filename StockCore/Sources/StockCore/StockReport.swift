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
