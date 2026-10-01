import Foundation
import Testing
@testable import StockCore

@Suite struct NetworkingTests {
    let url = URL(string: "https://data.sec.gov/submissions/CIK0000123456.json")!

    @Test func edgarClientSendsUserAgentAndReturnsBody() async throws {
        let stub = StubTransport()
        stub.respond(url.absoluteString, body: Data("ok".utf8))
        let data = try await testEDGARClient(stub).get(url)
        #expect(String(decoding: data, as: UTF8.self) == "ok")
        #expect(stub.requests.first?.headers["User-Agent"] == "StockWatcher test@example.com")
    }

    @Test func edgarClientRetriesRateLimitAndServerErrors() async throws {
        let stub = StubTransport()
        stub.respond(url.absoluteString, statuses: [429, 503, 200], body: Data("ok".utf8))
        let data = try await testEDGARClient(stub).get(url)
        #expect(String(decoding: data, as: UTF8.self) == "ok")
        #expect(stub.requestedURLs.count == 3)
    }

    @Test func edgarClientGivesUpAfterMaxRetries() async {
        let stub = StubTransport()
        stub.respond(url.absoluteString, statuses: [403])
        await #expect(throws: StockCoreError.http(status: 403, url: url.absoluteString)) {
            try await testEDGARClient(stub).get(url)
        }
        #expect(stub.requestedURLs.count == 3)  // first try + 2 retries
    }

    @Test func edgarClientDoesNotRetryNotFound() async {
        let stub = StubTransport()
        await #expect(throws: StockCoreError.http(status: 404, url: url.absoluteString)) {
            try await testEDGARClient(stub).get(url)
        }
        #expect(stub.requestedURLs.count == 1)
    }

    @Test func rateLimiterSpacesRequests() async {
        let limiter = RateLimiter(requestsPerSecond: 20)  // 50 ms apart
        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            for _ in 0..<4 { await limiter.acquire() }
        }
        #expect(elapsed >= .milliseconds(140))
    }
}
