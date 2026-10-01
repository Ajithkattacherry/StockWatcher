public struct ScoringEngine: Sendable {
    public static let insiderBonusBuyers = 3
    public static let insiderBonusPoints = 10.0
    public static let minimumPartsForTop10 = 3

    public init() {}

    public func score(company: Company, metrics: CompanyMetrics, table: PercentileTable) -> ScoreBreakdown {
        var oriented: [MetricID: Double] = [:]
        for (id, value) in metrics.values {
            guard let p = table.percentile(of: value, for: id) else { continue }
            oriented[id] = id.higherIsBetter ? p : 100 - p
        }
        if metrics.distinctInsiderBuyers >= Self.insiderBonusBuyers, let p = oriented[.insiderNetBuying] {
            oriented[.insiderNetBuying] = min(100, p + Self.insiderBonusPoints)
        }

        var partScores: [ScorePart: Double] = [:]
        for part in ScorePart.allCases {
            let ps = MetricID.allCases.filter { $0.part == part }.compactMap { oriented[$0] }
            if !ps.isEmpty { partScores[part] = ps.reduce(0, +) / Double(ps.count) }
        }

        let weightSum = partScores.keys.reduce(0.0) { $0 + $1.weight }
        let total: Double? = weightSum > 0
            ? partScores.reduce(0.0) { $0 + $1.key.weight * $1.value } / weightSum
            : nil

        let losingMoney = (metrics.latestNetIncome ?? 0) < 0 && (metrics.latestFreeCashFlow ?? 0) < 0
        let enoughParts = partScores.count >= Self.minimumPartsForTop10

        return ScoreBreakdown(
            total: total.map { Int($0.rounded()) },
            parts: partScores.mapValues { Int($0.rounded()) },
            metricPercentiles: oriented,
            isEligibleForTop10: enoughParts && !losingMoney && !company.isFinancial,
            limitedData: !enoughParts || company.isFinancial,
            reason: ReasonWriter.reason(percentiles: oriented, metrics: metrics))
    }
}
