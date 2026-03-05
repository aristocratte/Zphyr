//
//  Extensions.swift
//  Zphyr
//

import SwiftUI
import Foundation
import CryptoKit
import Security
import os

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

enum SecureLocalDataStore {
    static let encryptionEnabledKey = "zphyr.storage.encryption.enabled"

    private static let keychainService = "com.zphyr.app"
    private static let keychainAccount = "local-data-key-v1"
    private static let logger = Logger(subsystem: "com.zphyr.app", category: "SecureLocalDataStore")

    static func isEncryptionEnabled(defaults: UserDefaults = .standard) -> Bool {
        let value = defaults.object(forKey: encryptionEnabledKey)
        return value == nil ? true : defaults.bool(forKey: encryptionEnabledKey)
    }

    static func setEncryptionEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: encryptionEnabledKey)
    }

    @discardableResult
    static func save(_ data: Data, forKey key: String, defaults: UserDefaults = .standard) -> Bool {
        if isEncryptionEnabled(defaults: defaults) {
            guard let encrypted = encrypt(data) else {
                logger.error("[SecureStore] failed to encrypt payload for key \(key, privacy: .public)")
                return false
            }
            defaults.set(encrypted, forKey: encryptedKey(for: key))
            defaults.removeObject(forKey: key)
            return true
        } else {
            defaults.set(data, forKey: key)
            defaults.removeObject(forKey: encryptedKey(for: key))
            return true
        }
    }

    static func load(forKey key: String, defaults: UserDefaults = .standard) -> Data? {
        if isEncryptionEnabled(defaults: defaults) {
            if let encrypted = defaults.data(forKey: encryptedKey(for: key)),
               let decrypted = decrypt(encrypted) {
                return decrypted
            }
            if let plaintext = defaults.data(forKey: key) {
                _ = save(plaintext, forKey: key, defaults: defaults)
                return plaintext
            }
            return nil
        } else {
            if let plaintext = defaults.data(forKey: key) {
                return plaintext
            }
            if let encrypted = defaults.data(forKey: encryptedKey(for: key)),
               let decrypted = decrypt(encrypted) {
                defaults.set(decrypted, forKey: key)
                defaults.removeObject(forKey: encryptedKey(for: key))
                return decrypted
            }
            return nil
        }
    }

    static func removeValue(forKey key: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: encryptedKey(for: key))
    }

    private static func encryptedKey(for key: String) -> String {
        "\(key).enc"
    }

    private struct Envelope: Codable {
        let nonce: Data
        let ciphertext: Data
        let tag: Data
    }

    private static func encrypt(_ data: Data) -> Data? {
        guard let key = fetchOrCreateKey() else { return nil }
        do {
            let sealed = try AES.GCM.seal(data, using: key)
            let envelope = Envelope(
                nonce: Data(sealed.nonce),
                ciphertext: sealed.ciphertext,
                tag: sealed.tag
            )
            return try JSONEncoder().encode(envelope)
        } catch {
            logger.error("[SecureStore] encrypt failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func decrypt(_ encryptedPayload: Data) -> Data? {
        guard let key = fetchOrCreateKey() else { return nil }
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: encryptedPayload)
            let nonce = try AES.GCM.Nonce(data: envelope.nonce)
            let sealedBox = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: envelope.ciphertext,
                tag: envelope.tag
            )
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            logger.error("[SecureStore] decrypt failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func fetchOrCreateKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        func loadExistingKey() -> SymmetricKey? {
            var existing: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &existing)
            guard status == errSecSuccess else { return nil }
            guard let data = existing as? Data, data.count == 32 else { return nil }
            return SymmetricKey(data: data)
        }

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess, let key = loadExistingKey() {
            return key
        }

        guard status == errSecItemNotFound else {
            logger.error("[SecureStore] key lookup failed: \(status)")
            return nil
        }

        var keyBytes = Data(count: 32)
        let fillStatus = keyBytes.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
        }
        guard fillStatus == errSecSuccess else {
            logger.error("[SecureStore] random bytes generation failed: \(fillStatus)")
            return nil
        }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: keyBytes,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            logger.error("[SecureStore] key insert failed: \(addStatus)")
            return nil
        }

        if addStatus == errSecSuccess {
            return SymmetricKey(data: keyBytes)
        }

        // Another thread/process inserted the key first; always read canonical keychain value.
        if let key = loadExistingKey() {
            return key
        }

        logger.error("[SecureStore] duplicate key detected but fetch failed")
        return nil
    }
}
