import Foundation
import Testing
@testable import StockCore

@Suite struct DataSourceTests {
    // MARK: Fundamentals

    @Test func edgarFundamentalsCombineSubmissionsAndFacts() async throws {
        let stub = StubTransport()
        stub.respond(EDGARURL.submissions(cik: 123456).absoluteString,
                     body: try Fixture.data("submissions_sample.json"))
        stub.respond(EDGARURL.companyFacts(cik: 123456).absoluteString,
                     body: try Fixture.data("companyfacts_sample.json"))
        let source = EDGARFundamentalsSource(client: testEDGARClient(stub))
        let bundle = try await source.fundamentals(for: DirectoryEntry(ticker: "SMPL", cik: 123456, name: "Sample Corp"))
        #expect(bundle.company == Company(ticker: "SMPL", cik: 123456, name: "Sample Corp",
                                          sicCode: 3674, sector: "Semiconductors & Related Devices"))
        #expect(bundle.financials.count == 5)
        #expect(bundle.financials.last?.revenue == 190)
    }

    // MARK: Finnhub

    func finnhub(_ stub: StubTransport) -> FinnhubPriceSource {
        FinnhubPriceSource(apiKey: "KEY", transport: stub, limiter: RateLimiter(requestsPerSecond: 1_000))
    }
    func quoteURL(_ symbol: String) -> String { "https://finnhub.io/api/v1/quote?symbol=\(symbol)&token=KEY" }
    func metricURL(_ symbol: String) -> String {
        "https://finnhub.io/api/v1/stock/metric?symbol=\(symbol)&metric=all&token=KEY"
    }

    @Test func quoteCombinesPriceAndFirstAvailablePE() async throws {
        let stub = StubTransport()
        stub.respond(quoteURL("NOVA"), body: try Fixture.data("finnhub_quote.json"))
        stub.respond(metricURL("NOVA"), body: try Fixture.data("finnhub_metric.json"))
        let quote = try await finnhub(stub).quote(ticker: "nova")
        #expect(quote == PriceQuote(price: 142.3, peTTM: 38.4, asOf: "2026-09-30"))
    }

    @Test func classShareTickerUsesDotSymbol() async throws {
        #expect(FinnhubPriceSource.finnhubSymbol("BRK-B") == "BRK.B")
        #expect(FinnhubPriceSource.finnhubSymbol("brk.b") == "BRK.B")
        let stub = StubTransport()
        stub.respond(quoteURL("BRK.B"), body: try Fixture.data("finnhub_quote.json"))
        _ = try await finnhub(stub).quote(ticker: "BRK-B")
        #expect(stub.requestedURLs.first == quoteURL("BRK.B"))
    }

    @Test func zeroQuoteIsTreatedAsMissing() async {
        let stub = StubTransport()
        stub.respond(quoteURL("GONE"), body: Data(#"{"c":0,"d":null,"dp":null,"h":0,"l":0,"o":0,"pc":0,"t":0}"#.utf8))
        await #expect(throws: StockCoreError.missingData("No price for GONE")) {
            try await finnhub(stub).quote(ticker: "GONE")
        }
    }

    @Test func missingMetricsStillReturnAPrice() async throws {
        let stub = StubTransport()
        stub.respond(quoteURL("NOVA"), body: try Fixture.data("finnhub_quote.json"))
        let quote = try await finnhub(stub).quote(ticker: "NOVA")
        #expect(quote.price == 142.3)
        #expect(quote.peTTM == nil)
    }

    @Test func httpErrorsNeverLeakTheAPIKey() async {
        let stub = StubTransport()
        stub.respond(quoteURL("NOVA"), statuses: [429])
        do {
            _ = try await finnhub(stub).quote(ticker: "NOVA")
            Issue.record("Expected an error")
        } catch let StockCoreError.http(status, url) {
            #expect(status == 429)
            #expect(!url.contains("KEY"))
            #expect(url.contains("symbol=NOVA"))
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    // MARK: Holdings

    @Test func holdingsAreDecodedAndSorted() async throws {
        let file = HoldingsFile(schemaVersion: 1, ticker: "NOVA", quarters: [
            InstitutionalQuarter(period: "2026-06-30", totalShares: 1100, holderCount: 50),
            InstitutionalQuarter(period: "2026-03-31", totalShares: 1000, holderCount: 40),
        ])
        let stub = StubTransport()
        stub.respond("https://example.test/data/holdings/NOVA.json", body: try JSONEncoder().encode(file))
        let source = PublishedHoldingsSource(baseURL: URL(string: "https://example.test/data")!, transport: stub)
        let quarters = try await source.holdings(ticker: "NOVA")
        #expect(quarters.map(\.period) == ["2026-03-31", "2026-06-30"])
    }

    @Test func holdingsPathUsesNormalizedTicker() async throws {
        let stub = StubTransport()
        let source = PublishedHoldingsSource(baseURL: URL(string: "https://example.test/data")!, transport: stub)
        _ = try await source.holdings(ticker: "brk.b")
        #expect(stub.requestedURLs == ["https://example.test/data/holdings/BRK-B.json"])
    }

    @Test func missingHoldingsFileMeansNoData() async throws {
        let source = PublishedHoldingsSource(baseURL: URL(string: "https://example.test/data")!,
                                             transport: StubTransport())
        #expect(try await source.holdings(ticker: "NOVA").isEmpty)
    }
}
