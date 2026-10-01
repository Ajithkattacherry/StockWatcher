import Foundation
import Testing
@testable import StockCore

@Suite struct Form4Tests {
    @Test func parsesAnOpenMarketPurchase() throws {
        let txs = try Form4Parser.transactions(from: Fixture.data("form4_purchase.xml"))
        #expect(txs.count == 1)
        let tx = try #require(txs.first)
        #expect(tx.ownerName == "Doe Jane")
        #expect(tx.ownerCik == 1234567)
        #expect(tx.isDirector && !tx.isOfficer)
        #expect(tx.officerTitle == nil)
        #expect(tx.date == "2026-08-12")
        #expect(tx.code == "P")
        #expect(tx.shares == 1000)
        #expect(tx.pricePerShare == 50.25)
        #expect(tx.value == 50_250)
        #expect(!tx.isPlanned10b51)
    }

    @Test func plannedSaleFlagsEveryRowAndTrimsTimezoneFromDates() throws {
        let txs = try Form4Parser.transactions(from: Fixture.data("form4_planned_sale.xml"))
        #expect(txs.map(\.code) == ["M", "S"])
        #expect(txs.allSatisfy { $0.isPlanned10b51 })
        #expect(txs.allSatisfy { $0.isOfficer && $0.officerTitle == "Chief Financial Officer" })
        #expect(txs[1].date == "2026-06-01")
    }

    @Test func footnoteMentioning10b51MarksThePlan() throws {
        let xml = """
        <ownershipDocument>
          <reportingOwner><reportingOwnerId><rptOwnerName>Old Style</rptOwnerName></reportingOwnerId></reportingOwner>
          <nonDerivativeTable><nonDerivativeTransaction>
            <transactionDate><value>2022-03-01</value></transactionDate>
            <transactionCoding><transactionCode>S</transactionCode></transactionCoding>
            <transactionAmounts><transactionShares><value>10</value></transactionShares>
              <transactionPricePerShare><value>5</value><footnoteId id="F1"/></transactionPricePerShare></transactionAmounts>
          </nonDerivativeTransaction></nonDerivativeTable>
          <footnotes><footnote id="F1">Sold under a Rule 10b5-1 trading plan adopted May 2021.</footnote></footnotes>
        </ownershipDocument>
        """
        let txs = try Form4Parser.transactions(from: Data(xml.utf8))
        #expect(txs.first?.isPlanned10b51 == true)
    }

    @Test func rowsMissingRequiredFieldsAreSkipped() throws {
        let xml = """
        <ownershipDocument>
          <reportingOwner><reportingOwnerId><rptOwnerName>X</rptOwnerName></reportingOwnerId></reportingOwner>
          <nonDerivativeTable><nonDerivativeTransaction>
            <transactionCoding><transactionCode>P</transactionCode></transactionCoding>
          </nonDerivativeTransaction></nonDerivativeTable>
        </ownershipDocument>
        """
        #expect(try Form4Parser.transactions(from: Data(xml.utf8)).isEmpty)
    }

    @Test func malformedOrWrongDocumentsThrow() {
        #expect(throws: StockCoreError.self) {
            try Form4Parser.transactions(from: Data("<ownershipDocument><broken".utf8))
        }
        #expect(throws: StockCoreError.self) {
            try Form4Parser.transactions(from: Data("<html><body>hi</body></html>".utf8))
        }
    }

    @Test func insiderSourceFetchesRecentForm4sAndSkipsBadOnes() async throws {
        let stub = StubTransport()
        stub.respond(EDGARURL.submissions(cik: 123456).absoluteString,
                     body: try Fixture.data("submissions_sample.json"))
        let aug = EDGARURL.filingDocument(cik: 123456, accession: "0000123456-26-000050",
                                          primaryDocument: "xslF345X05/form4-aug.xml")
        let jun = EDGARURL.filingDocument(cik: 123456, accession: "0000123456-26-000030",
                                          primaryDocument: "xslF345X05/form4-jun.xml")
        let old = EDGARURL.filingDocument(cik: 123456, accession: "0000123456-25-000010",
                                          primaryDocument: "xslF345X05/form4-old.xml")
        stub.respond(aug.absoluteString, body: try Fixture.data("form4_purchase.xml"))
        stub.respond(jun.absoluteString, body: Data("<ownershipDocument><broken".utf8))

        let source = EDGARInsiderSource(client: testEDGARClient(stub))
        let txs = try await source.insiderTransactions(cik: 123456, since: "2026-03-31")

        #expect(txs.map(\.ownerName) == ["Doe Jane"])
        #expect(stub.requestedURLs.contains(jun.absoluteString))
        #expect(!stub.requestedURLs.contains(old.absoluteString))
    }

    @Test func insiderSourceRespectsMaxFilings() async throws {
        let stub = StubTransport()
        stub.respond(EDGARURL.submissions(cik: 123456).absoluteString,
                     body: try Fixture.data("submissions_sample.json"))
        let source = EDGARInsiderSource(client: testEDGARClient(stub), maxFilings: 1)
        _ = try await source.insiderTransactions(cik: 123456, since: "2026-03-31")
        #expect(stub.requestedURLs.count == 2)  // submissions + one Form 4
    }
}
