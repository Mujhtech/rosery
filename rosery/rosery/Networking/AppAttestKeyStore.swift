import Foundation
import Security

/// The Keychain survives reinstall; the install marker deliberately does not.
/// App Attest's private keys themselves are invalidated by reinstall/migration.
nonisolated struct AppAttestKeyStore {
    private let account: String
    private let service = "mujhtech.rosery.api-attest"

    init(baseURL: URL, defaults: UserDefaults = .standard) {
        let markerKey = "rosery.api.install-id.v1"
        let installID: String
        if let existing = defaults.string(forKey: markerKey) {
            installID = existing
        } else {
            installID = UUID().uuidString
            defaults.set(installID, forKey: markerKey)
        }
        account = baseURL.absoluteString + ":" + installID
    }

    func load() throws -> EnrollmentRecord? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw RoseryAPIError.keyStorageFailed(status)
        }
        return try JSONDecoder().decode(EnrollmentRecord.self, from: data)
    }

    func save(_ record: EnrollmentRecord) throws {
        let data = try JSONEncoder().encode(record)
        let updated = SecItemUpdate(baseQuery as CFDictionary,
                                    [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else {
            throw RoseryAPIError.keyStorageFailed(updated)
        }
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw RoseryAPIError.keyStorageFailed(status) }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw RoseryAPIError.keyStorageFailed(status)
        }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

nonisolated struct EnrollmentRecord: Codable, Sendable {
    let keyID: String
    var registered = false
    var challenge: EnrollmentChallenge?
    var attestation: String?
}

nonisolated struct EnrollmentChallenge: Codable, Sendable {
    let challenge: String
    let expiresAt: Date
}
