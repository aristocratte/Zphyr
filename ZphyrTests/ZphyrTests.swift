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

    @Test func dictionaryLearningDetectsSingleWordReplacement() {
        let suggestion = DictationEngine._test_detectWordReplacement(
            from: "Le modèle quen est rapide.",
            to: "Le modèle qwen est rapide."
        )
        #expect(suggestion?.mistakenWord == "quen")
        #expect(suggestion?.correctedWord == "qwen")
    }

    @Test func dictionaryLearningDetectsInWordCharacterCorrection() {
        let suggestion = DictationEngine._test_detectWordReplacement(
            from: "Version en cours: qun3.",
            to: "Version en cours: qwen3."
        )
        #expect(suggestion?.mistakenWord == "qun3")
        #expect(suggestion?.correctedWord == "qwen3")
    }

    @Test func dictionaryLearningRejectsMultiWordEdits() {
        let suggestion = DictationEngine._test_detectWordReplacement(
            from: "Bonjour monde",
            to: "Bonjour beau monde"
        )
        #expect(suggestion == nil)
    }

    @Test func dictionaryLearningTokenBoundaryMatch() {
        #expect(DictationEngine._test_containsLearningToken("quen", in: "Le mot quen a été dicté."))
        #expect(!DictationEngine._test_containsLearningToken("quen", in: "Le mot quentin a été dicté."))
    }

}
