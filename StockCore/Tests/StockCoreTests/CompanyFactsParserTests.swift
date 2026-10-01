import Foundation
import Testing
@testable import StockCore

@Suite struct CompanyFactsParserTests {
    func parse(maxYears: Int = 5) throws -> [AnnualFinancials] {
        try CompanyFactsParser.annualFinancials(from: Fixture.data("companyfacts_sample.json"),
                                                maxYears: maxYears)
    }

    @Test func mergesRevenueTagsAcrossATagSwitch() throws {
        let years = try parse()
        #expect(years.map(\.periodEnd) == ["2020-12-31", "2021-12-31", "2022-12-31", "2023-12-31", "2024-12-31"])
        #expect(years[0].revenue == 80)    // only in the old "Revenues" tag
        #expect(years[1].revenue == 100)   // priority tag beats the old tag's 99
    }

    @Test func latestFiledValueWinsForRestatements() throws {
        #expect(try parse()[3].revenue == 151)
    }

    @Test func ignoresQuarterlyFactsInsideAnnualFilings() throws {
        #expect(try parse().last?.revenue == 190)
    }

    @Test func fillsEveryFieldForTheLatestYear() throws {
        let latest = try #require(try parse().last)
        #expect(latest.epsDiluted == 2.10)
        #expect(latest.netIncome == 21)
        #expect(latest.operatingIncome == 34)
        #expect(latest.operatingCashFlow == 30)
        #expect(latest.capitalExpenditure == 8)
        #expect(latest.freeCashFlow == 22)
        #expect(latest.longTermDebt == 45)
        #expect(latest.cash == 20)
    }

    @Test func balanceSheetValuesComeFromAnnualReportsOnly() throws {
        let years = try parse()
        #expect(years[3].longTermDebt == 50)
        #expect(years[3].cash == nil)
    }

    @Test func limitsToMostRecentYears() throws {
        #expect(try parse(maxYears: 4).map(\.periodEnd).first == "2021-12-31")
    }

    @Test func companyWithoutUSGAAPFactsHasNoYears() throws {
        let json = #"{"cik":1,"entityName":"Shell","facts":{"dei":{}}}"#
        #expect(try CompanyFactsParser.annualFinancials(from: Data(json.utf8)).isEmpty)
    }

    @Test func malformedJSONThrows() {
        #expect(throws: StockCoreError.self) {
            try CompanyFactsParser.annualFinancials(from: Data("not json".utf8))
        }
    }
}
