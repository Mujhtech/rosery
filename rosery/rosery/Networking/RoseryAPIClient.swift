import CryptoKit
import DeviceCheck
import Foundation

/// An accountless client. Construct explicitly when Quran content is requested;
/// initialization and existing app screens never start networking.
actor RoseryAPIClient {
    private let baseURL: URL
    private let transport = RoseryAPITransport()
    private let keyStore: AppAttestKeyStore
    private let attest = DCAppAttestService.shared
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(baseURL: URL, allowInsecureLocalhost: Bool = false) throws {
        try RoseryAPIProtocol.validateBaseURL(baseURL, allowInsecureLocalhost: allowInsecureLocalhost)
        self.baseURL = baseURL
        keyStore = AppAttestKeyStore(baseURL: baseURL)
    }

    func chapters(language: String = "en") async throws -> [QuranChapter] {
        try RoseryAPIProtocol.validateLanguage(language)
        let data = try await get(path: "/v1/quran/chapters", query: [.init(name: "language", value: language)])
        return try JSONDecoder().decode(ChapterList.self, from: data).chapters
    }

    func chapter(_ id: Int, language: String = "en") async throws -> QuranChapter {
        guard (1...114).contains(id) else { throw RoseryAPIError.invalidArgument }
        try RoseryAPIProtocol.validateLanguage(language)
        let data = try await get(path: "/v1/quran/chapters/\(id)", query: [.init(name: "language", value: language)])
        return try JSONDecoder().decode(ChapterDetail.self, from: data).chapter
    }

    func verses(chapter id: Int, page: Int = 1, perPage: Int = 20,
                language: String = "en") async throws -> QuranVersePage {
        guard (1...114).contains(id), (1...604).contains(page), (1...50).contains(perPage) else {
            throw RoseryAPIError.invalidArgument
        }
        try RoseryAPIProtocol.validateLanguage(language)
        let data = try await get(path: "/v1/quran/verses/by_chapter/\(id)", query: [
            .init(name: "page", value: String(page)),
            .init(name: "per_page", value: String(perPage)),
            .init(name: "language", value: language),
            .init(name: "words", value: "false")
        ])
        return try JSONDecoder().decode(QuranVersePage.self, from: data)
    }

    /// Deliberate repair after confirmed enrollment loss or an API-origin change.
    /// Never call automatically for a generic401, timeout, or network failure.
    /// A new key must complete normal Apple proof and server registration again.
    func resetEnrollment() async throws {
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        try keyStore.clear()
    }

    private func get(path: String, query: [URLQueryItem]) async throws -> Data {
        // An actor alone is reentrant across awaits. Hold this FIFO permit through
        // challenge, assertion and response to keep secure-enclave counters ordered.
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        guard attest.isSupported else { throw RoseryAPIError.unsupportedDevice }
        for attempt in 0..<2 {
            do {
                let keyID = try await enrollIfNeeded()
                let challenge = try await fetchChallenge(keyID: keyID, purpose: "assert")
                var request = URLRequest(url: try RoseryAPIProtocol.url(baseURL: baseURL, path: path, query: query))
                request.httpMethod = "GET"
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let clientData = try RoseryAPIProtocol.clientData(challenge: challenge.challenge, request: request)
                let assertion = try await attest.generateAssertion(keyID, clientDataHash: Data(SHA256.hash(data: clientData)))
                request.setValue(keyID, forHTTPHeaderField: "X-App-Attest-Key-ID")
                request.setValue(challenge.challenge, forHTTPHeaderField: "X-App-Attest-Challenge")
                request.setValue(assertion.base64EncodedString(), forHTTPHeaderField: "X-App-Attest-Assertion")
                return try await send(request, expectedStatus: 200)
            } catch let error as DCError where error.code == .invalidKey && attempt == 0 {
                // Only Apple's confirmed invalid key permits automatic replacement;
                // an HTTP401 never silently resets registration or weakens security.
                try keyStore.clear()
            }
        }
        throw RoseryAPIError.invalidResponse
    }

    private func enrollIfNeeded() async throws -> String {
        var record: EnrollmentRecord
        if let stored = try keyStore.load() {
            record = stored
        } else {
            record = EnrollmentRecord(keyID: try await attest.generateKey())
            try keyStore.save(record)
        }
        if record.registered { return record.keyID }

        // Preserve generated attestation bytes until the server acknowledges them.
        // Repeating this exact registration is idempotent on the Go API.
        if let object = record.attestation, let challenge = record.challenge {
            do {
                try await register(record.keyID, challenge: challenge.challenge, attestation: object)
                try confirm(&record)
                return record.keyID
            } catch RoseryAPIError.server(let status, _, _) where status == 401 {
                // This known enrollment was rejected; recreate on a later call.
                try keyStore.clear()
                throw RoseryAPIError.enrollmentExpired
            }
        }

        if let challenge = record.challenge, challenge.expiresAt <= Date() {
            // An ambiguous Apple attempt must never be retried with a new nonce
            // against the same key after its challenge has expired.
            try keyStore.clear()
            throw RoseryAPIError.enrollmentExpired
        }
        if record.challenge == nil {
            record.challenge = try await fetchChallenge(keyID: record.keyID, purpose: "attest")
            try keyStore.save(record)
        }
        guard let challenge = record.challenge,
              let rawChallenge = Data(base64Encoded: challenge.challenge) else {
            throw RoseryAPIError.invalidResponse
        }
        let hash = Data(SHA256.hash(data: rawChallenge))
        let object = try await attestWithRetry(keyID: record.keyID, hash: hash, expiresAt: challenge.expiresAt)
        record.attestation = object.base64EncodedString()
        try keyStore.save(record)
        try await register(record.keyID, challenge: challenge.challenge, attestation: object.base64EncodedString())
        try confirm(&record)
        return record.keyID
    }

    private func confirm(_ record: inout EnrollmentRecord) throws {
        record.registered = true
        record.challenge = nil
        record.attestation = nil
        try keyStore.save(record)
    }

    private func attestWithRetry(keyID: String, hash: Data, expiresAt: Date) async throws -> Data {
        for attempt in 0..<3 {
            try Task.checkCancellation()
            guard expiresAt > Date() else { throw RoseryAPIError.enrollmentExpired }
            do {
                return try await attest.attestKey(keyID, clientDataHash: hash)
            } catch let error as DCError {
                if error.code == .serverUnavailable {
                    guard attempt < 2 else { throw error }
                    try await Task.sleep(for: .seconds(1 << attempt))
                } else {
                    // Apple says a candidate whose attestation failed with a
                    // nontransient error must not be used. This only discards
                    // pending enrollment; assertion input errors never erase a
                    // previously registered key.
                    try keyStore.clear()
                    if error.code == .featureUnsupported {
                        throw RoseryAPIError.unsupportedDevice
                    }
                    throw error
                }
            }
        }
        throw RoseryAPIError.invalidResponse
    }

    private func register(_ keyID: String, challenge: String, attestation: String) async throws {
        let payload = Registration(keyID: keyID, challenge: challenge, attestation: attestation)
        _ = try await post(path: "/v1/attest/register", body: payload, expectedStatus: 204)
    }

    private func fetchChallenge(keyID: String, purpose: String) async throws -> EnrollmentChallenge {
        let data = try await post(path: "/v1/attest/challenge", body: ChallengeRequest(keyID: keyID, purpose: purpose),
                                  expectedStatus: 200)
        let reply = try JSONDecoder().decode(ChallengeReply.self, from: data)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractional = formatter.date(from: reply.expiresAt)
        formatter.formatOptions = [.withInternetDateTime]
        guard let expiry = fractional ?? formatter.date(from: reply.expiresAt), expiry > Date(),
              let nonce = Data(base64Encoded: reply.challenge), nonce.count == 32 else {
            throw RoseryAPIError.invalidResponse
        }
        return EnrollmentChallenge(challenge: reply.challenge, expiresAt: expiry)
    }

    private func post<T: Encodable>(path: String, body: T, expectedStatus: Int) async throws -> Data {
        var request = URLRequest(url: try RoseryAPIProtocol.url(baseURL: baseURL, path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request, expectedStatus: expectedStatus)
    }

    private func send(_ request: URLRequest, expectedStatus: Int) async throws -> Data {
        let (data, response) = try await transport.send(request)
        guard response.statusCode == expectedStatus else {
            throw RoseryAPIProtocol.responseError(status: response.statusCode, data: data,
                                                  retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
        }
        return data
    }

    private func acquire() async throws {
        if !busy { busy = true; return }
        guard waiters.count < 16 else { throw RoseryAPIError.requestQueueFull }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }

    private struct ChallengeRequest: Encodable {
        let keyID: String
        let purpose: String
        enum CodingKeys: String, CodingKey { case keyID = "key_id", purpose }
    }
    private struct ChallengeReply: Decodable {
        let challenge: String
        let expiresAt: String
        enum CodingKeys: String, CodingKey { case challenge, expiresAt = "expires_at" }
    }
    private struct Registration: Encodable {
        let keyID: String
        let challenge: String
        let attestation: String
        enum CodingKeys: String, CodingKey { case keyID = "key_id", challenge, attestation }
    }
    private struct ChapterList: Decodable { let chapters: [QuranChapter] }
    private struct ChapterDetail: Decodable { let chapter: QuranChapter }
}
