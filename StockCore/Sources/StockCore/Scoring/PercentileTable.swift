/// S&P 500 distribution of each metric, as 101 cut points (0th…100th percentile).
/// Published nightly so the phone can score watchlist stocks on the same scale.
public struct PercentileTable: Codable, Hashable, Sendable {
    public var cutPoints: [MetricID: [Double]]

    public init(cutPoints: [MetricID: [Double]]) {
        self.cutPoints = cutPoints
    }

    public static func build(from population: [CompanyMetrics]) -> PercentileTable {
        var cuts: [MetricID: [Double]] = [:]
        for id in MetricID.allCases {
            let values = population.compactMap { $0[id] }.filter(\.isFinite).sorted()
            guard !values.isEmpty else { continue }
            cuts[id] = (0...100).map { quantile(values, index: $0) }
        }
        return PercentileTable(cutPoints: cuts)
    }

    /// Linear-interpolated quantile at index/100. Integer arithmetic keeps
    /// positions exact (n = 101 gives cut point i == sorted[i]).
    static func quantile(_ sorted: [Double], index: Int) -> Double {
        let numerator = index * (sorted.count - 1)
        let lower = numerator / 100
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = Double(numerator % 100) / 100
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    /// Raw percentile 0…100 (higher value → higher percentile). Ties get the
    /// midpoint of the cut points they span.
    public func percentile(of value: Double, for id: MetricID) -> Double? {
        guard let c = cutPoints[id], c.count == 101, value.isFinite else { return nil }
        if value < c[0] { return 0 }
        if value > c[100] { return 100 }
        if let first = c.firstIndex(of: value), let last = c.lastIndex(of: value) {
            return Double(first + last) / 2
        }
        // c[0] < value < c[100] and value isn't a cut point, so i is in 1...100.
        guard let i = c.firstIndex(where: { $0 > value }) else { return 100 }
        return Double(i - 1) + (value - c[i - 1]) / (c[i] - c[i - 1])
    }
}
