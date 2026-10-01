import Testing
@testable import StockCore

@Suite struct TopPickerTests {
    func entry(_ ticker: String, total: Int?, growth: Int = 50, eligible: Bool = true)
        -> (company: Company, score: ScoreBreakdown) {
        (Company(ticker: ticker, cik: 1, name: "\(ticker) Inc"),
         ScoreBreakdown(total: total, parts: [.growth: growth], metricPercentiles: [:],
                        isEligibleForTop10: eligible, limitedData: !eligible, reason: "r-\(ticker)"))
    }

    @Test func ranksEligibleByScoreThenGrowthThenTicker() {
        let picks = TopPicker.pick([
            entry("LOW", total: 60),
            entry("BANK", total: 99, eligible: false),
            entry("TIEB", total: 80, growth: 70),
            entry("TIEA", total: 80, growth: 90),
            entry("SAME2", total: 70, growth: 50),
            entry("SAME1", total: 70, growth: 50),
            entry("NONE", total: nil),
        ])
        #expect(picks.map(\.ticker) == ["TIEA", "TIEB", "SAME1", "SAME2", "LOW"])
        #expect(picks.map(\.rank) == [1, 2, 3, 4, 5])
        #expect(picks[0].score == 80)
        #expect(picks[0].reason == "r-TIEA")
        #expect(picks[0].name == "TIEA Inc")
    }

    @Test func limitsToCount() {
        let many = (0..<25).map { (i: Int) in entry("T\(i)", total: i) }
        #expect(TopPicker.pick(many).count == 10)
        #expect(TopPicker.pick(many).first?.ticker == "T24")
        #expect(TopPicker.pick(many, count: 3).count == 3)
    }
}
