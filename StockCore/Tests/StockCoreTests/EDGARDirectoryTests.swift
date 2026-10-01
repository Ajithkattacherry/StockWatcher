import Foundation
import Testing
@testable import StockCore

@Suite struct EDGARDirectoryTests {
    @Test func buildsEDGARURLs() {
        #expect(EDGARURL.paddedCIK(320193) == "0000320193")
        #expect(EDGARURL.submissions(cik: 123456).absoluteString
                == "https://data.sec.gov/submissions/CIK0000123456.json")
        #expect(EDGARURL.companyFacts(cik: 123456).absoluteString
                == "https://data.sec.gov/api/xbrl/companyfacts/CIK0000123456.json")
    }

    @Test func filingDocumentStripsXSLRendererPrefix() {
        let url = EDGARURL.filingDocument(cik: 123456, accession: "0000123456-26-000050",
                                          primaryDocument: "xslF345X05/form4-aug.xml")
        #expect(url.absoluteString
                == "https://www.sec.gov/Archives/edgar/data/123456/000012345626000050/form4-aug.xml")
        let plain = EDGARURL.filingDocument(cik: 1, accession: "0000000001-26-000001",
                                            primaryDocument: "doc.xml")
        #expect(plain.absoluteString.hasSuffix("/000000000126000001/doc.xml"))
    }

    @Test func lookupNormalizesClassShareTickers() throws {
        let dir = try CompanyDirectory(secTickersJSON: Fixture.data("company_tickers_sample.json"))
        #expect(dir.lookup(ticker: "BRK.B")?.cik == 1067983)
        #expect(dir.lookup(ticker: "brk-b")?.cik == 1067983)
        #expect(dir.lookup(ticker: " BRK/B ")?.cik == 1067983)
        #expect(dir.lookup(ticker: "ZZZZ") == nil)
    }

    @Test func duplicateTickersKeepTheFirstRow() throws {
        let dir = try CompanyDirectory(secTickersJSON: Fixture.data("company_tickers_sample.json"))
        #expect(dir.lookup(ticker: "AAPL")?.cik == 320193)
    }

    @Test func searchRanksExactThenPrefixThenName() throws {
        let dir = try CompanyDirectory(secTickersJSON: Fixture.data("company_tickers_sample.json"))
        #expect(dir.search("goog").map(\.ticker) == ["GOOG", "GOOGL"])
        #expect(dir.search("alphabet").map(\.ticker) == ["GOOGL", "GOOG"])
        #expect(dir.search("nvidia", limit: 1).map(\.ticker) == ["NVDA"])
        #expect(dir.search("  ").isEmpty)
    }

    @Test func parsesSubmissions() throws {
        let s = try EDGARSubmissions(jsonData: Fixture.data("submissions_sample.json"))
        #expect(s.name == "Sample Corp")
        #expect(s.sicCode == 3674)
        #expect(s.sicDescription == "Semiconductors & Related Devices")
        #expect(s.recentFilings.count == 4)
        #expect(s.recentFilings[0] == FilingRef(accessionNumber: "0000123456-26-000050",
                                                filingDate: "2026-08-15", form: "4",
                                                primaryDocument: "xslF345X05/form4-aug.xml"))
    }

    @Test func emptySICBecomesNil() throws {
        let json = #"{"name":"X","sic":"","sicDescription":"","filings":{"recent":{"accessionNumber":[],"filingDate":[],"form":[],"primaryDocument":[]}}}"#
        let s = try EDGARSubmissions(jsonData: Data(json.utf8))
        #expect(s.sicCode == nil)
        #expect(s.sicDescription == nil)
    }

    @Test func malformedSubmissionsThrow() {
        #expect(throws: StockCoreError.self) { try EDGARSubmissions(jsonData: Data("nope".utf8)) }
    }
}
