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
