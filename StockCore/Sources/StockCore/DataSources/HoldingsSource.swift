import Foundation

/// holdings/{TICKER}.json as published by the pipeline (Plan 2).
public struct HoldingsFile: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var ticker: String
    public var quarters: [InstitutionalQuarter]

    public init(schemaVersion: Int, ticker: String, quarters: [InstitutionalQuarter]) {
        self.schemaVersion = schemaVersion
        self.ticker = ticker
        self.quarters = quarters
    }
}

public protocol HoldingsSource: Sendable {
    /// Oldest → newest; empty when no 13F data exists for the ticker.
    func holdings(ticker: String) async throws -> [InstitutionalQuarter]
}

public struct PublishedHoldingsSource: HoldingsSource {
    let baseURL: URL
    let transport: any HTTPTransport

    public init(baseURL: URL, transport: any HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.transport = transport
    }

    public func holdings(ticker: String) async throws -> [InstitutionalQuarter] {
        let url = baseURL
            .appendingPathComponent("holdings")
            .appendingPathComponent("\(CompanyDirectory.normalize(ticker)).json")
        let response = try await transport.get(url, headers: [:])
        if response.status == 404 { return [] }
        guard (200..<300).contains(response.status) else {
            throw StockCoreError.http(status: response.status, url: url.absoluteString)
        }
        do {
            return try JSONDecoder().decode(HoldingsFile.self, from: response.body)
                .quarters.sorted { $0.period < $1.period }
        } catch {
            throw StockCoreError.malformed("holdings \(ticker): \(error)")
        }
    }
}
