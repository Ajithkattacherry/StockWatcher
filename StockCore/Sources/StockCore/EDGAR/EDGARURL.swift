import Foundation

public enum EDGARURL {
    public static let companyTickers = URL(string: "https://www.sec.gov/files/company_tickers.json")!

    public static func paddedCIK(_ cik: Int) -> String {
        let digits = String(cik)
        return String(repeating: "0", count: max(0, 10 - digits.count)) + digits
    }

    public static func submissions(cik: Int) -> URL {
        URL(string: "https://data.sec.gov/submissions/CIK\(paddedCIK(cik)).json")!
    }

    public static func companyFacts(cik: Int) -> URL {
        URL(string: "https://data.sec.gov/api/xbrl/companyfacts/CIK\(paddedCIK(cik)).json")!
    }

    /// Raw filing document. EDGAR lists Form 4s as "xslF345X05/file.xml" (an HTML
    /// rendering); dropping the xsl folder gives the original XML.
    public static func filingDocument(cik: Int, accession: String, primaryDocument: String) -> URL {
        var parts = primaryDocument.split(separator: "/").map(String.init)
        if parts.count > 1, parts[0].hasPrefix("xsl") {
            parts.removeFirst()
        }
        let folder = accession.replacingOccurrences(of: "-", with: "")
        return URL(string: "https://www.sec.gov/Archives/edgar/data/\(cik)/\(folder)/\(parts.joined(separator: "/"))")!
    }
}
