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
