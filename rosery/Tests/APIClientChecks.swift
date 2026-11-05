import CryptoKit
import Foundation

/// Runs on macOS with the three platform-neutral networking files; no device,
/// API account, Keychain access or real network connection is involved.
@main
struct APIClientChecks {
    static func main() async throws {
        try checkConfiguration()
        try checkCanonicalRequest()
        try checkModelsAndErrors()
        try await checkTransport()
        print("API client checks passed")
    }

    static func checkConfiguration() throws {
        try RoseryAPIProtocol.validateBaseURL(URL(string: "https://api.example.com")!)
        for value in ["http://api.example.com", "https://user:secret@api.example.com",
                      "https://api.example.com/path", "https://api.example.com?token=x",
                      "https://api.example.com#fragment", "file:///tmp/api"] {
            do {
                try RoseryAPIProtocol.validateBaseURL(URL(string: value)!)
                throw CheckFailure("Accepted an unsafe API base URL")
            } catch RoseryAPIError.invalidConfiguration { }
        }
        try RoseryAPIProtocol.validateLanguage("en")
        try RoseryAPIProtocol.validateLanguage("eng")
        for language in ["", "EN", "en&words=true", "../", "e", "en-us", "engl"] {
            do {
                try RoseryAPIProtocol.validateLanguage(language)
                throw CheckFailure("Accepted an invalid language")
            } catch RoseryAPIError.invalidArgument { }
        }
    }

    static func checkCanonicalRequest() throws {
        let challenge = Data(repeating: 7, count: 32).base64EncodedString()
        let url = try RoseryAPIProtocol.url(baseURL: URL(string: "https://api.example.com")!,
                                            path: "/v1/quran/chapters",
                                            query: [.init(name: "language", value: "en"),
                                                    .init(name: "page", value: "1")])
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let actual = try RoseryAPIProtocol.clientData(challenge: challenge, request: request)
        let emptySHA256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        let expected = "rosery-v1\n\(challenge)\nGET\n/v1/quran/chapters?language=en&page=1\n\(emptySHA256)"
        try require(String(decoding: actual, as: UTF8.self) == expected, "Canonical bytes differ from Go protocol")
        // Shared with the Go verifier test; computed independently with hashlib.
        let expectedDigest = "821dcc033488fb08e892feeeccc1eb05b0610223fa2ed48072c380be9ce33a34"
        let digest = SHA256.hash(data: actual).map { String(format: "%02x", $0) }.joined()
        try require(digest == expectedDigest, "Swift/Go canonical request hash differs")
        request.httpMethod = "POST"
        request.httpBody = Data("test".utf8)
        let post = try RoseryAPIProtocol.clientData(challenge: challenge, request: request)
        try require(actual != post, "Request method/body are not bound")
        let reordered = URL(string: "https://api.example.com/v1/quran/chapters?page=1&language=en")!
        request = URLRequest(url: reordered)
        try require(try RoseryAPIProtocol.clientData(challenge: challenge, request: request) != actual,
                    "Query order was not bound")
    }

    static func checkModelsAndErrors() throws {
        let page = Data(#"{"verses":[{"id":1,"verse_number":1,"verse_key":"1:1","text_uthmani":"بِسْمِ"}],"pagination":{"current_page":1,"next_page":null,"total_pages":1}}"#.utf8)
        let result = try JSONDecoder().decode(QuranVersePage.self, from: page)
        try require(result.verses.first?.textUthmani == "بِسْمِ", "Arabic text changed")
        let errorData = Data(#"{"error":{"code":"rate_limited","message":"Slow down"}}"#.utf8)
        guard case .server(429, "rate_limited", 30) = RoseryAPIProtocol.responseError(status: 429, data: errorData,
                                                                                  retryAfter: "30") else {
            throw CheckFailure("Server error or retry delay was not preserved")
        }
    }

    static func checkTransport() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [APIFixtureProtocol.self]
        let transport = RoseryAPITransport(configuration: configuration)
        let (success, response) = try await transport.send(URLRequest(url: URL(string: "https://fixture.invalid/success")!))
        try require(response.statusCode == 200 && success == Data(#"{"value":1}"#.utf8), "Transport lost response")
        let (_, limited) = try await transport.send(URLRequest(url: URL(string: "https://fixture.invalid/rate-limited")!))
        try require(limited.statusCode == 429 && limited.value(forHTTPHeaderField: "Retry-After") == "30",
                    "Transport lost status/Retry-After")
        for path in ["oversized-header", "oversized-stream"] {
            do {
                _ = try await transport.send(URLRequest(url: URL(string: "https://fixture.invalid/\(path)")!))
                throw CheckFailure("Response size was not bounded")
            } catch RoseryAPIError.responseTooLarge { }
        }
    }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw CheckFailure(message) }
    }

    struct CheckFailure: Error { let message: String; init(_ message: String) { self.message = message } }
}

nonisolated final class APIFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        var data = Data(#"{"value":1}"#.utf8)
        var status = 200
        var headers = ["Content-Type": "application/json"]
        switch url.path {
        case "/rate-limited":
            status = 429
            headers["Retry-After"] = "30"
        case "/oversized-header":
            headers["Content-Length"] = String(RoseryAPIProtocol.maximumResponseBytes + 1)
        case "/oversized-stream":
            data = Data(repeating: 65, count: RoseryAPIProtocol.maximumResponseBytes + 1)
        default: break
        }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { }
}
