import Foundation

/// SEC Form 4 ownership XML → non-derivative transactions.
public enum Form4Parser {
    public static func transactions(from data: Data) throws -> [InsiderTransaction] {
        let root = try MiniXMLParser.parse(data)
        guard root.name == "ownershipDocument" else {
            throw StockCoreError.malformed("Expected ownershipDocument, found \(root.name)")
        }

        let owner = root.first("reportingOwner")
        let ownerName = owner?.string("reportingOwnerId", "rptOwnerName") ?? "Unknown"
        let ownerCik = owner?.string("reportingOwnerId", "rptOwnerCik").flatMap { Int($0) }
        let isOfficer = owner?.flag("reportingOwnerRelationship", "isOfficer") ?? false
        let isDirector = owner?.flag("reportingOwnerRelationship", "isDirector") ?? false
        let officerTitle = owner?.string("reportingOwnerRelationship", "officerTitle")

        // Filings since April 2023 have an explicit checkbox; older ones say so in a footnote.
        let footnotes = root.first("footnotes")?.all("footnote").map(\.text).joined(separator: " ") ?? ""
        let planned = root.flag("aff10b5One")
            || footnotes.range(of: "10b5-1", options: .caseInsensitive) != nil

        let rows = root.first("nonDerivativeTable")?.all("nonDerivativeTransaction") ?? []
        return rows.compactMap { row in
            guard let date = row.string("transactionDate", "value"),
                  let code = row.string("transactionCoding", "transactionCode"),
                  let shares = row.string("transactionAmounts", "transactionShares", "value").flatMap({ Double($0) })
            else { return nil }
            let price = row.string("transactionAmounts", "transactionPricePerShare", "value").flatMap { Double($0) }
            return InsiderTransaction(ownerName: ownerName, ownerCik: ownerCik, isOfficer: isOfficer,
                                      isDirector: isDirector, officerTitle: officerTitle,
                                      date: String(date.prefix(10)), code: code, shares: shares,
                                      pricePerShare: price, isPlanned10b51: planned)
        }
    }
}
