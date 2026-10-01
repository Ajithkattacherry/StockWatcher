import Foundation

public protocol PriceSource: Sendable {
    func quote(ticker: String) async throws -> PriceQuote
}

/// Finnhub free tier: 60 calls/minute, personal use. Two calls per quote.
public struct FinnhubPriceSource: PriceSource {
    public static let baseURL = URL(string: "https://finnhub.io/api/v1")!
    static let peKeys = ["peTTM", "peExclExtraTTM", "peBasicExclExtraTTM"]

    let apiKey: String
    let transport: any HTTPTransport
    let limiter: RateLimiter

    public init(apiKey: String,
                transport: any HTTPTransport = URLSessionTransport(),
                limiter: RateLimiter = RateLimiter(requestsPerSecond: 55.0 / 60.0)) {
        self.apiKey = apiKey
        self.transport = transport
        self.limiter = limiter
    }

    /// Finnhub writes class shares with a dot ("BRK.B"); EDGAR uses a dash.
    public static func finnhubSymbol(_ ticker: String) -> String {
        CompanyDirectory.normalize(ticker).replacingOccurrences(of: "-", with: ".")
    }

    private struct QuoteDTO: Decodable {
        let c: Double
        let t: Double?
    }

    /// Finnhub metric values are mostly numbers but include nulls and date strings.
    private struct LenientDouble: Decodable {
        let value: Double?
        init(from decoder: Decoder) throws {
            value = try? decoder.singleValueContainer().decode(Double.self)
        }
    }

    private struct MetricDTO: Decodable {
        let metric: [String: LenientDouble]
    }

    public func quote(ticker: String) async throws -> PriceQuote {
        let symbol = Self.finnhubSymbol(ticker)
        let quote: QuoteDTO = try await fetch(url("quote", [URLQueryItem(name: "symbol", value: symbol)]))
        // Unknown and delisted symbols come back as all zeros rather than an error.
        guard quote.c > 0, let timestamp = quote.t, timestamp > 0 else {
            throw StockCoreError.missingData("No price for \(symbol)")
        }
        let metrics: MetricDTO? = try? await fetch(url("stock/metric", [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "metric", value: "all"),
        ]))
        let pe = Self.peKeys.lazy.compactMap { metrics?.metric[$0]?.value }.first
        return PriceQuote(price: quote.c, peTTM: pe,
                          asOf: ISODay.string(Date(timeIntervalSince1970: timestamp)))
    }

    private func url(_ path: String, _ items: [URLQueryItem]) -> URL {
        let endpoint = path.split(separator: "/").reduce(Self.baseURL) {
            $0.appendingPathComponent(String($1))
        }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = items + [URLQueryItem(name: "token", value: apiKey)]
        return components.url!
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        await limiter.acquire()
        let response = try await transport.get(url, headers: [:])
        guard (200..<300).contains(response.status) else {
            throw StockCoreError.http(status: response.status, url: Self.redacted(url))
        }
        do {
            return try JSONDecoder().decode(T.self, from: response.body)
        } catch {
            throw StockCoreError.malformed("Finnhub \(url.path): \(error)")
        }
    }

    static func redacted(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.path }
        components.queryItems = components.queryItems?.filter { $0.name != "token" }
        return components.string ?? url.path
    }
}
