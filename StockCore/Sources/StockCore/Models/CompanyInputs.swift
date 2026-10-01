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
