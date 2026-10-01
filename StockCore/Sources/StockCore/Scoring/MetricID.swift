public enum ScorePart: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
    case growth, smartMoney, quality, valuation

    public var weight: Double {
        switch self {
        case .growth: 0.40
        case .smartMoney: 0.30
        case .quality: 0.20
        case .valuation: 0.10
        }
    }
}

public enum MetricID: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
    case revenueCAGR3Y, epsCAGR3Y, growthAcceleration
    case insiderNetBuying, institutionalShareChange, holderCountChange
    case operatingMarginTrend, freeCashFlowMargin, netDebtToFCF
    case peg

    public var part: ScorePart {
        switch self {
        case .revenueCAGR3Y, .epsCAGR3Y, .growthAcceleration: .growth
        case .insiderNetBuying, .institutionalShareChange, .holderCountChange: .smartMoney
        case .operatingMarginTrend, .freeCashFlowMargin, .netDebtToFCF: .quality
        case .peg: .valuation
        }
    }

    public var higherIsBetter: Bool {
        switch self {
        case .netDebtToFCF, .peg: false
        default: true
        }
    }
}
