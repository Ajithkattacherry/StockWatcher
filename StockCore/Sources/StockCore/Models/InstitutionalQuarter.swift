/// 13F aggregate for one ticker at one quarter end.
public struct InstitutionalQuarter: Codable, Hashable, Sendable {
    public var period: String
    public var totalShares: Double
    public var holderCount: Int

    public init(period: String, totalShares: Double, holderCount: Int) {
        self.period = period
        self.totalShares = totalShares
        self.holderCount = holderCount
    }
}
