import Foundation

public protocol InsiderSource: Sendable {
    /// Transactions dated on or after `since` ("yyyy-MM-dd"), newest first.
    func insiderTransactions(cik: Int, since: String) async throws -> [InsiderTransaction]
}

public struct EDGARInsiderSource: InsiderSource {
    let client: EDGARClient
    let maxFilings: Int

    public init(client: EDGARClient, maxFilings: Int = 60) {
        self.client = client
        self.maxFilings = maxFilings
    }

    public func insiderTransactions(cik: Int, since: String) async throws -> [InsiderTransaction] {
        let submissions = try EDGARSubmissions(jsonData: try await client.get(EDGARURL.submissions(cik: cik)))
        let filings = submissions.recentFilings
            .filter { $0.form == "4" && $0.filingDate >= since }
            .prefix(maxFilings)

        var result: [InsiderTransaction] = []
        for filing in filings {
            let url = EDGARURL.filingDocument(cik: cik, accession: filing.accessionNumber,
                                              primaryDocument: filing.primaryDocument)
            // One unreadable filing must not hide the rest.
            guard let data = try? await client.get(url),
                  let transactions = try? Form4Parser.transactions(from: data) else { continue }
            result += transactions.filter { $0.date >= since }
        }
        return result.sorted { $0.date > $1.date }
    }
}
