import Foundation
import Testing
@testable import StockCore

@Suite struct PercentileTableTests {
    func population(_ values: [Double], _ id: MetricID = .revenueCAGR3Y) -> [CompanyMetrics] {
        values.map { CompanyMetrics(values: [id: $0]) }
    }

    @Test func buildsOneHundredOneCutPoints() {
        let table = PercentileTable.build(from: population((0...100).map(Double.init)))
        #expect(table.cutPoints[.revenueCAGR3Y] == (0...100).map(Double.init))
        #expect(table.cutPoints[.peg] == nil)
    }

    @Test func percentileInterpolatesAndClamps() {
        let table = PercentileTable.build(from: population((0...100).map(Double.init)))
        #expect(table.percentile(of: 50, for: .revenueCAGR3Y) == 50)
        #expect(approx(table.percentile(of: 50.5, for: .revenueCAGR3Y), 50.5))
        #expect(table.percentile(of: -5, for: .revenueCAGR3Y) == 0)
        #expect(table.percentile(of: 500, for: .revenueCAGR3Y) == 100)
    }

    @Test func tiesGetTheMidpoint() {
        let table = PercentileTable.build(from: population([0, 0, 0, 0, 10]))
        #expect(table.percentile(of: 0, for: .revenueCAGR3Y) == 37.5)
        #expect(table.percentile(of: 10, for: .revenueCAGR3Y) == 100)
        #expect(approx(table.percentile(of: 5, for: .revenueCAGR3Y), 87.5))
    }

    @Test func singleValuePopulationIsFiftieth() {
        let table = PercentileTable.build(from: population([3]))
        #expect(table.percentile(of: 3, for: .revenueCAGR3Y) == 50)
    }

    @Test func missingMetricOrNonFiniteValueIsNil() {
        let table = PercentileTable.build(from: population([1, 2, 3]))
        #expect(table.percentile(of: 1, for: .peg) == nil)
        #expect(table.percentile(of: .nan, for: .revenueCAGR3Y) == nil)
    }

    @Test func ignoresCompaniesMissingTheMetric() {
        var pop = population([1, 2, 3])
        pop.append(CompanyMetrics(values: [.peg: 2]))
        let table = PercentileTable.build(from: pop)
        #expect(table.cutPoints[.revenueCAGR3Y]?.first == 1)
        #expect(table.cutPoints[.revenueCAGR3Y]?.last == 3)
    }

    @Test func roundTripsThroughJSON() throws {
        let table = PercentileTable.build(from: population([1, 2, 3]))
        let data = try JSONEncoder().encode(table)
        #expect(try JSONDecoder().decode(PercentileTable.self, from: data) == table)
    }
}
