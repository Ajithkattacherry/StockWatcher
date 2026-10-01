import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPResponse: Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

public protocol HTTPTransport: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        // Continuation form works on both Apple platforms and Linux FoundationNetworking.
        return try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                continuation.resume(returning: HTTPResponse(status: status, body: data ?? Data()))
            }.resume()
        }
    }
}
