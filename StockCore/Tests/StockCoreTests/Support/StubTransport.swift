import Foundation
@testable import StockCore

/// In-memory HTTP: each URL has a queue of responses; the last one repeats.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    struct Request: Sendable {
        let url: String
        let headers: [String: String]
    }

    private let lock = NSLock()
    private var routes: [String: [HTTPResponse]] = [:]
    private var log: [Request] = []

    func respond(_ url: String, status: Int = 200, body: Data) {
        lock.withLock { routes[url] = [HTTPResponse(status: status, body: body)] }
    }

    func respond(_ url: String, statuses: [Int], body: Data = Data()) {
        lock.withLock { routes[url] = statuses.map { HTTPResponse(status: $0, body: body) } }
    }

    var requests: [Request] { lock.withLock { log } }
    var requestedURLs: [String] { requests.map(\.url) }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        lock.withLock {
            log.append(Request(url: url.absoluteString, headers: headers))
            guard var queue = routes[url.absoluteString], !queue.isEmpty else {
                return HTTPResponse(status: 404, body: Data())
            }
            let response = queue.count > 1 ? queue.removeFirst() : queue[0]
            routes[url.absoluteString] = queue
            return response
        }
    }
}

func testEDGARClient(_ stub: StubTransport) -> EDGARClient {
    EDGARClient(userAgent: "StockWatcher test@example.com", transport: stub,
                limiter: RateLimiter(requestsPerSecond: 1_000), maxRetries: 2,
                baseBackoff: .milliseconds(1))
}
