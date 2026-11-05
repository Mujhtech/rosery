import CryptoKit
import Foundation

nonisolated enum RoseryAPIError: Error, Sendable {
    case invalidConfiguration
    case invalidArgument
    case unsupportedDevice
    case invalidResponse
    case responseTooLarge
    case requestQueueFull
    case keyStorageFailed(Int32)
    case enrollmentExpired
    case server(status: Int, code: String, retryAfter: TimeInterval?)
}

/// Wire rules shared with the Go API. No user identity or shared app secret is used.
nonisolated enum RoseryAPIProtocol {
    static let maximumResponseBytes = 2 * 1024 * 1024

    static func validateBaseURL(_ url: URL, allowInsecureLocalhost: Bool = false) throws {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else {
            throw RoseryAPIError.invalidConfiguration
        }
        if parts.scheme == "https" { return }
        #if DEBUG
        if allowInsecureLocalhost, parts.scheme == "http",
           ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased()) {
            return
        }
        #endif
        throw RoseryAPIError.invalidConfiguration
    }

    static func url(baseURL: URL, path: String, query: [URLQueryItem] = []) throws -> URL {
        guard path.hasPrefix("/v1/"),
              var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw RoseryAPIError.invalidArgument
        }
        parts.path = path
        parts.queryItems = query.isEmpty ? nil : query
        guard let result = parts.url else { throw RoseryAPIError.invalidArgument }
        return result
    }

    static func clientData(challenge: String, request: URLRequest) throws -> Data {
        guard let url = request.url,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let nonce = Data(base64Encoded: challenge), nonce.count == 32 else {
            throw RoseryAPIError.invalidArgument
        }
        let target = parts.percentEncodedPath + (parts.percentEncodedQuery.map { "?" + $0 } ?? "")
        let bodyHash = SHA256.hash(data: request.httpBody ?? Data())
            .map { String(format: "%02x", $0) }.joined()
        return Data("rosery-v1\n\(challenge)\n\((request.httpMethod ?? "GET").uppercased())\n\(target)\n\(bodyHash)".utf8)
    }

    static func validateLanguage(_ language: String) throws {
        guard (2...3).contains(language.utf8.count),
              language.utf8.allSatisfy({ (97...122).contains($0) }) else {
            throw RoseryAPIError.invalidArgument
        }
    }

    static func responseError(status: Int, data: Data, retryAfter: String?) -> RoseryAPIError {
        let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
        return .server(status: status, code: envelope?.error.code ?? "http_error",
                       retryAfter: retryAfter.flatMap(TimeInterval.init))
    }

    private struct ErrorEnvelope: Decodable {
        let error: Detail
        struct Detail: Decodable { let code: String }
    }
}
