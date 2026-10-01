public struct RankedPick: Codable, Hashable, Sendable {
    public var rank: Int
    public var ticker: String
    public var name: String
    public var score: Int
    public var reason: String

    public init(rank: Int, ticker: String, name: String, score: Int, reason: String) {
        self.rank = rank
        self.ticker = ticker
        self.name = name
        self.score = score
        self.reason = reason
    }
}

public enum TopPicker {
    public static func pick(_ scored: [(company: Company, score: ScoreBreakdown)], count: Int = 10) -> [RankedPick] {
        let ranked = scored
            .compactMap { entry -> (company: Company, score: ScoreBreakdown, total: Int)? in
                guard entry.score.isEligibleForTop10, let total = entry.score.total else { return nil }
                return (entry.company, entry.score, total)
            }
            .sorted { a, b in
                if a.total != b.total { return a.total > b.total }
                let ga = a.score.parts[.growth] ?? 0, gb = b.score.parts[.growth] ?? 0
                if ga != gb { return ga > gb }
                return a.company.ticker < b.company.ticker
            }
        return ranked.prefix(count).enumerated().map { index, entry in
            RankedPick(rank: index + 1, ticker: entry.company.ticker, name: entry.company.name,
                       score: entry.total, reason: entry.score.reason)
        }
    }
}
