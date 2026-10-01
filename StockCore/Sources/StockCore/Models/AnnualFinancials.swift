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
