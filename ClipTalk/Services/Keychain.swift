import Foundation
import Security

/// Storage for the user's OpenAI API key.
///
/// Tries the macOS Keychain first (secure, encrypted). Falls back to a file
/// in Application Support for Debug / unsigned builds where Keychain writes
/// can silently fail. Once the app is signed & notarized in Phase 6, the
/// Keychain path will always work.
///
/// Values are cached in memory after the first read so we don't trigger
/// a system permission dialog on every access during a bulk operation.
enum Keychain {

    private static let service = "com.sunghun.ClipTalk"
    private static let openAIAccount = "openai_api_key"

    // In-memory cache, set on first successful read or write.
    private static var cachedKey: String?
    private static let cacheLock = NSLock()

    /// Plain-text fallback file for unsigned builds.
    private static var fallbackURL: URL {
        LibraryPaths.supportDir
            .appendingPathComponent("openai_key.txt")
    }

    // MARK: - Public

    static func getOpenAIKey() -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = cachedKey, !cached.isEmpty {
            return cached
        }
        if let viaKeychain = readKeychain(account: openAIAccount), !viaKeychain.isEmpty {
            cachedKey = viaKeychain
            return viaKeychain
        }
        if let viaFile = readFallback(), !viaFile.isEmpty {
            cachedKey = viaFile
            return viaFile
        }
        return nil
    }

    /// Saves the key, returning true only if it actually persisted.
    @discardableResult
    static func setOpenAIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)

        cacheLock.lock()
        cachedKey = trimmed.isEmpty ? nil : trimmed
        cacheLock.unlock()

        if trimmed.isEmpty {
            deleteKeychain(account: openAIAccount)
            try? FileManager.default.removeItem(at: fallbackURL)
            return true
        }

        let viaKeychain = writeKeychain(account: openAIAccount, value: trimmed)
        if viaKeychain {
            // If Keychain worked, wipe any stale fallback file.
            try? FileManager.default.removeItem(at: fallbackURL)
            return true
        }
        // Fallback to file write so the app actually works.
        return writeFallback(trimmed)
    }

    static func clearOpenAIKey() {
        cacheLock.lock()
        cachedKey = nil
        cacheLock.unlock()

        deleteKeychain(account: openAIAccount)
        try? FileManager.default.removeItem(at: fallbackURL)
    }

    // MARK: - Keychain implementation

    private static func readKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    @discardableResult
    private static func writeKeychain(account: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    private static func deleteKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - File fallback (unsigned builds only)

    private static func readFallback() -> String? {
        guard let raw = try? String(contentsOf: fallbackURL, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @discardableResult
    private static func writeFallback(_ value: String) -> Bool {
        do {
            try value.write(to: fallbackURL, atomically: true, encoding: .utf8)
            // Restrict permissions: owner-only read/write.
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fallbackURL.path
            )
            return true
        } catch {
            return false
        }
    }
}
