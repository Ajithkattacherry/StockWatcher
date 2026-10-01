public struct PriceQuote: Codable, Hashable, Sendable {
    public var price: Double
    /// Trailing-twelve-month P/E. Nil or ≤ 0 when earnings are negative or unknown.
    public var peTTM: Double?
    public var asOf: String

    public init(price: Double, peTTM: Double?, asOf: String) {
        self.price = price
        self.peTTM = peTTM
        self.asOf = asOf
    }
}
