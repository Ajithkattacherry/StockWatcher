import Foundation

public struct FilingRef: Codable, Hashable, Sendable {
    public var accessionNumber: String
    public var filingDate: String
    public var form: String
    public var primaryDocument: String

    public init(accessionNumber: String, filingDate: String, form: String, primaryDocument: String) {
        self.accessionNumber = accessionNumber
        self.filingDate = filingDate
        self.form = form
        self.primaryDocument = primaryDocument
    }
}

/// data.sec.gov/submissions/CIK##########.json — company profile and recent filings.
public struct EDGARSubmissions: Sendable {
    public var name: String
    public var sicCode: Int?
    public var sicDescription: String?
    /// Newest first, as EDGAR returns them.
    public var recentFilings: [FilingRef]

    private struct DTO: Decodable {
        let name: String
        let sic: String?
        let sicDescription: String?
        let filings: Filings

        struct Filings: Decodable { let recent: Recent }
        struct Recent: Decodable {
            let accessionNumber: [String]
            let filingDate: [String]
            let form: [String]
            let primaryDocument: [String]
        }
    }

    public init(jsonData: Data) throws {
        let dto: DTO
        do {
            dto = try JSONDecoder().decode(DTO.self, from: jsonData)
        } catch {
            throw StockCoreError.malformed("submissions: \(error)")
        }
        let recent = dto.filings.recent
        let count = min(recent.accessionNumber.count, recent.filingDate.count,
                        recent.form.count, recent.primaryDocument.count)
        name = dto.name
        sicCode = dto.sic.flatMap { Int($0) }
        sicDescription = dto.sicDescription.flatMap { $0.isEmpty ? nil : $0 }
        recentFilings = (0..<count).map {
            FilingRef(accessionNumber: recent.accessionNumber[$0], filingDate: recent.filingDate[$0],
                      form: recent.form[$0], primaryDocument: recent.primaryDocument[$0])
        }
    }
}
