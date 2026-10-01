import Foundation

public struct FundamentalsBundle: Codable, Hashable, Sendable {
    public var company: Company
    public var financials: [AnnualFinancials]

    public init(company: Company, financials: [AnnualFinancials]) {
        self.company = company
        self.financials = financials
    }
}

public protocol FundamentalsSource: Sendable {
    func fundamentals(for entry: DirectoryEntry) async throws -> FundamentalsBundle
}

public struct EDGARFundamentalsSource: FundamentalsSource {
    let client: EDGARClient

    public init(client: EDGARClient) {
        self.client = client
    }

    public func fundamentals(for entry: DirectoryEntry) async throws -> FundamentalsBundle {
        async let submissionsData = client.get(EDGARURL.submissions(cik: entry.cik))
        async let factsData = client.get(EDGARURL.companyFacts(cik: entry.cik))
        let submissions = try EDGARSubmissions(jsonData: try await submissionsData)
        let financials = try CompanyFactsParser.annualFinancials(from: try await factsData)
        let company = Company(ticker: entry.ticker, cik: entry.cik, name: entry.name,
                              sicCode: submissions.sicCode, sector: submissions.sicDescription)
        return FundamentalsBundle(company: company, financials: financials)
    }
}
