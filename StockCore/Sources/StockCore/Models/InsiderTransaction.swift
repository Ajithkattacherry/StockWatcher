/// One row of a Form 4 non-derivative table.
public struct InsiderTransaction: Codable, Hashable, Sendable {
    public var ownerName: String
    public var ownerCik: Int?
    public var isOfficer: Bool
    public var isDirector: Bool
    public var officerTitle: String?
    public var date: String
    /// SEC transaction code: "P" open-market buy, "S" open-market sale, others ignored by scoring.
    public var code: String
    public var shares: Double
    public var pricePerShare: Double?
    public var isPlanned10b51: Bool

    public init(ownerName: String, ownerCik: Int?, isOfficer: Bool, isDirector: Bool,
                officerTitle: String?, date: String, code: String, shares: Double,
                pricePerShare: Double?, isPlanned10b51: Bool) {
        self.ownerName = ownerName
        self.ownerCik = ownerCik
        self.isOfficer = isOfficer
        self.isDirector = isDirector
        self.officerTitle = officerTitle
        self.date = date
        self.code = code
        self.shares = shares
        self.pricePerShare = pricePerShare
        self.isPlanned10b51 = isPlanned10b51
    }

    public var value: Double { shares * (pricePerShare ?? 0) }
}
