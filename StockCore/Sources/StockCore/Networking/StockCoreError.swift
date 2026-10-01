public enum StockCoreError: Error, Equatable, Sendable {
    case http(status: Int, url: String)
    case missingData(String)
    case malformed(String)
}
