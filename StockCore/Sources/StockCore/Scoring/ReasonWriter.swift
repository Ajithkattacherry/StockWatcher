import Foundation

/// Builds the one-line "why it ranked" from the two strongest metrics.
enum ReasonWriter {
    static func reason(percentiles: [MetricID: Double], metrics: CompanyMetrics) -> String {
        percentiles
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue }
            .prefix(2)
            .map { phrase(for: $0.key, percentile: $0.value, metrics: metrics) }
            .joined(separator: " · ")
    }

    static func phrase(for id: MetricID, percentile: Double, metrics: CompanyMetrics) -> String {
        let top = max(1, Int((100 - percentile).rounded()))
        let raw = metrics[id] ?? 0
        switch id {
        case .revenueCAGR3Y:
            return "Top \(top)% revenue growth"
        case .epsCAGR3Y:
            return "Top \(top)% earnings growth"
        case .growthAcceleration:
            return raw > 0 ? "Growth accelerating" : "Top \(top)% growth trend"
        case .insiderNetBuying:
            let n = metrics.distinctInsiderBuyers
            return n > 0 ? "\(n) insider\(n == 1 ? "" : "s") bought recently" : "Top \(top)% insider activity"
        case .institutionalShareChange:
            return raw > 0 ? "Funds adding shares" : "Top \(top)% fund interest"
        case .holderCountChange:
            return raw > 0 ? "More funds holding" : "Top \(top)% fund interest"
        case .operatingMarginTrend:
            return raw > 0 ? "Margins expanding" : "Top \(top)% margin trend"
        case .freeCashFlowMargin:
            return "Top \(top)% cash generation"
        case .netDebtToFCF:
            return "Low debt"
        case .peg:
            return "PEG \(String(format: "%.1f", raw))"
        }
    }
}
