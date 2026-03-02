//
//  ZphyrTests.swift
//  ZphyrTests
//
//  Created by Aristide Cordonnier on 01/03/2026.
//

import Testing
import Foundation
@testable import Zphyr

struct ZphyrTests {

    @Test func supportedUILanguageFallbackToEnglish() {
        let language = SupportedUILanguage.fromWhisperCode("de")
        #expect(language == .en)
    }

    @Test func triggerKeyCodesAreUnique() {
        let codes = TriggerKey.allCases.map(\.keyCode)
        #expect(Set(codes).count == codes.count)
    }

    @Test func secureStoreMigratesPlaintextToEncrypted() {
        let suiteName = "zphyr.tests.\(UUID().uuidString)"
        let storageKey = "sample.key"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let payload = Data("hello zphyr".utf8)
        defaults.set(payload, forKey: storageKey)
        SecureLocalDataStore.setEncryptionEnabled(true, defaults: defaults)

        let loaded = SecureLocalDataStore.load(forKey: storageKey, defaults: defaults)
        #expect(loaded == payload)
        #expect(defaults.data(forKey: storageKey) == nil)
        #expect(defaults.data(forKey: "\(storageKey).enc") != nil)
    }

}
