import Foundation

public struct DirectoryEntry: Codable, Hashable, Sendable {
    public var ticker: String
    public var cik: Int
    public var name: String

    public init(ticker: String, cik: Int, name: String) {
        self.ticker = ticker
        self.cik = cik
        self.name = name
    }
}

/// Ticker ↔ CIK map from the SEC's company_tickers.json.
public struct CompanyDirectory: Sendable {
    public let entries: [DirectoryEntry]
    private let byTicker: [String: DirectoryEntry]

    public init(entries: [DirectoryEntry]) {
        self.entries = entries
        var map: [String: DirectoryEntry] = [:]
        for entry in entries where map[Self.normalize(entry.ticker)] == nil {
            map[Self.normalize(entry.ticker)] = entry
        }
        byTicker = map
    }

    public init(secTickersJSON data: Data) throws {
        struct Row: Decodable {
            let cik_str: Int
            let ticker: String
            let title: String
        }
        let rows: [String: Row]
        do {
            rows = try JSONDecoder().decode([String: Row].self, from: data)
        } catch {
            throw StockCoreError.malformed("company_tickers.json: \(error)")
        }
        // The SEC file is keyed "0", "1", … roughly by size; keep that order so
        // the first row wins when a ticker appears twice.
        let entries = rows
            .sorted { (Int($0.key) ?? .max) < (Int($1.key) ?? .max) }
            .map { DirectoryEntry(ticker: $0.value.ticker, cik: $0.value.cik_str, name: $0.value.title) }
        self.init(entries: entries)
    }

    /// EDGAR style: uppercase, class separator "-" ("brk.b" → "BRK-B").
    public static func normalize(_ ticker: String) -> String {
        ticker.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }

    public func lookup(ticker: String) -> DirectoryEntry? {
        byTicker[Self.normalize(ticker)]
    }

    /// Exact ticker, then ticker prefix, then name contains — deduplicated.
    public func search(_ query: String, limit: Int = 20) -> [DirectoryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, limit > 0 else { return [] }
        let normalized = Self.normalize(trimmed)

        let exact = entries.filter { Self.normalize($0.ticker) == normalized }
        let prefix = entries
            .filter { Self.normalize($0.ticker).hasPrefix(normalized) && Self.normalize($0.ticker) != normalized }
            .sorted { $0.ticker < $1.ticker }
        let byName = entries.filter { $0.name.range(of: trimmed, options: .caseInsensitive) != nil }

        var seen = Set<String>()
        var results: [DirectoryEntry] = []
        for entry in exact + prefix + byName where seen.insert(entry.ticker).inserted {
            results.append(entry)
            if results.count == limit { break }
        }
        return results
    }
}
