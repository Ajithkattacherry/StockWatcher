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
