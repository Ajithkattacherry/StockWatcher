import Foundation

/// SEC EDGAR access: declared User-Agent, ≤ 8 requests/second, exponential
/// backoff on 403/429/5xx (SEC uses 403 when it throttles).
/// Share one client per process: the rate limit lives in its `RateLimiter`.
public struct EDGARClient: Sendable {
    public let userAgent: String
    let transport: any HTTPTransport
    let limiter: RateLimiter
    let maxRetries: Int
    let baseBackoff: Duration

    public init(userAgent: String,
                transport: any HTTPTransport = URLSessionTransport(),
                limiter: RateLimiter = RateLimiter(requestsPerSecond: 8),
                maxRetries: Int = 4,
                baseBackoff: Duration = .seconds(10)) {
        self.userAgent = userAgent
        self.transport = transport
        self.limiter = limiter
        self.maxRetries = maxRetries
        self.baseBackoff = baseBackoff
    }

    public func get(_ url: URL) async throws -> Data {
        var attempt = 0
        while true {
            await limiter.acquire()
            let response = try await transport.get(url, headers: ["User-Agent": userAgent])
            if (200..<300).contains(response.status) {
                return response.body
            }
            let retryable = response.status == 403 || response.status == 429
                || (500..<600).contains(response.status)
            if retryable && attempt < maxRetries {
                try await Task.sleep(for: baseBackoff * (1 << attempt))
                attempt += 1
                continue
            }
            throw StockCoreError.http(status: response.status, url: url.absoluteString)
        }
    }
}
