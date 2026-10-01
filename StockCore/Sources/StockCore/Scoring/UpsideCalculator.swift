import Foundation

public struct UpsideScenario: Codable, Hashable, Sendable {
    public var assumedPE: Double
    public var impliedPrice: Double
    /// Fractional change from today's price: 0.74 means +74%.
    public var upside: Double

    public init(assumedPE: Double, impliedPrice: Double, upside: Double) {
        self.assumedPE = assumedPE
        self.impliedPrice = impliedPrice
        self.upside = upside
    }
}

public struct UpsideResult: Codable, Hashable, Sendable {
    /// Assumed EPS growth for each of the next three years.
    public var growthPath: [Double]
    public var ifGrowthContinues: UpsideScenario?
    public var ifPEMovesToSectorMedian: UpsideScenario?
    public var unavailableReason: String?

    public init(growthPath: [Double], ifGrowthContinues: UpsideScenario?,
                ifPEMovesToSectorMedian: UpsideScenario?, unavailableReason: String?) {
        self.growthPath = growthPath
        self.ifGrowthContinues = ifGrowthContinues
        self.ifPEMovesToSectorMedian = ifPEMovesToSectorMedian
        self.unavailableReason = unavailableReason
    }

    static func unavailable(_ reason: String) -> UpsideResult {
        UpsideResult(growthPath: [], ifGrowthContinues: nil, ifPEMovesToSectorMedian: nil,
                     unavailableReason: reason)
    }
}

/// Scenarios, not predictions: "if earnings keep growing like this, and the market
/// values them at this P/E, the price in 3 years would be about X".
public enum UpsideCalculator {
    public static let growthCap = 0.25
    public static let taper = 0.8
    public static let years = 3

    public static func calculate(price: Double?, peTTM: Double?, epsCAGR: Double?,
                                 sectorMedianPE: Double?) -> UpsideResult {
        guard let price, price > 0 else {
            return .unavailable("No current price is available.")
        }
        guard let pe = peTTM, pe > 0 else {
            return .unavailable("The company isn't profitable yet, so there's no P/E to project from.")
        }
        guard let growth = epsCAGR else {
            return .unavailable("There isn't enough earnings history to estimate growth.")
        }

        let start = min(growth, growthCap)
        let path = (0..<years).map { start * pow(taper, Double($0)) }
        let factor = path.reduce(1.0) { $0 * (1 + $1) }
        let eps = price / pe

        func scenario(_ multiple: Double) -> UpsideScenario {
            let implied = eps * factor * multiple
            return UpsideScenario(assumedPE: multiple, impliedPrice: implied, upside: implied / price - 1)
        }

        let sector = sectorMedianPE.flatMap { $0 > 0 ? scenario($0) : nil }
        return UpsideResult(growthPath: path, ifGrowthContinues: scenario(pe),
                            ifPEMovesToSectorMedian: sector, unavailableReason: nil)
    }
}
