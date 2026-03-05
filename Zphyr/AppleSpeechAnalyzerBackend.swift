import Foundation
import AVFoundation
import Speech
import os

@MainActor
final class AppleSpeechAnalyzerBackend: ASRService {
    private let log = Logger(subsystem: "com.zphyr.app", category: "AppleASR")

    static var isRuntimeSupported: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    /// Prevents concurrent SpeechAnalyzer sessions (would crash with "Cannot simultaneously analyze").
    private var isTranscribing = false

    let descriptor = ASRBackendDescriptor(
        kind: .appleSpeechAnalyzer,
        displayName: "Apple Speech Analyzer",
        requiresModelInstall: false,
        modelSizeLabel: nil,
        onboardingSubtitle: "Apple Speech Analyzer runs locally with no model download.",
        approxModelBytes: nil
    )

    func transcribe(audioBuffer: [Float]) async throws -> String {
        guard !audioBuffer.isEmpty else { throw ASRBackendError.invalidAudioBuffer }
        guard Self.isRuntimeSupported else {
            throw ASRBackendError.unsupported("Apple Speech backend is not available on this macOS version.")
        }
        guard !isTranscribing else {
            throw ASRBackendError.transcriptionFailed("A transcription is already in progress.")
        }
        isTranscribing = true
        defer { isTranscribing = false }

        let fileURL = try writeTemporaryAudioFile(audioBuffer)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        if #available(macOS 26.0, *) {
            do {
                let text = try await transcribeWithSpeechAnalyzer(fileURL)
                if !text.isEmpty { return text }
            } catch {
                // Fall back to legacy Speech API below.
            }
        }

        if #available(macOS 15.0, *) {
            return try await transcribeWithLegacySpeechRecognizer(fileURL)
        }

        throw ASRBackendError.unsupported("Apple Speech backend is not available on this macOS version.")
    }

    private func writeTemporaryAudioFile(_ samples: [Float]) throws -> URL {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )
        guard let format else { throw ASRBackendError.invalidAudioBuffer }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw ASRBackendError.invalidAudioBuffer
        }
        pcm.frameLength = frameCount
        guard let channelData = pcm.floatChannelData?[0] else {
            throw ASRBackendError.invalidAudioBuffer
        }
        samples.withUnsafeBufferPointer { buffer in
            channelData.update(from: buffer.baseAddress!, count: samples.count)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zphyr-apple-asr-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: pcm)
        return url
    }

    @available(macOS 26.0, *)
    private func transcribeWithSpeechAnalyzer(_ audioURL: URL) async throws -> String {
        guard SpeechTranscriber.isAvailable else {
            throw ASRBackendError.unsupported("SpeechAnalyzer transcriber is not available on this machine.")
        }

        guard let locale = await resolvedSpeechAnalyzerLocale() else {
            throw ASRBackendError.unsupported("No supported SpeechTranscriber locale is available on this machine.")
        }
        let preferredLanguage = preferredLanguageIdentifier()
        if Self.languageCode(from: locale.identifier) != Self.languageCode(from: preferredLanguage) {
            log.notice("[AppleASR] locale fallback preferred=\(preferredLanguage, privacy: .public) selected=\(locale.identifier, privacy: .public)")
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let audioFile = try AVAudioFile(forReading: audioURL)

        // Init with inputAudioFile + finishAfterFile automatically starts analysis.
        // Do NOT call analyzer.start() again — that causes
        // "Cannot simultaneously analyze multiple input sequences".
        let analyzer = try await SpeechAnalyzer(
            inputAudioFile: audioFile,
            modules: [transcriber],
            options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .lingering),
            analysisContext: .init(),
            finishAfterFile: true,
            volatileRangeChangedHandler: nil
        )
        _ = analyzer // keep alive while iterating results

        var candidate = ""
        var assembledSegments: [String] = []
        for try await result in transcriber.results {
            let fragment = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fragment.isEmpty else { continue }
            if fragment.count > candidate.count {
                // Keep longest hypothesis (many APIs emit cumulative text here).
                candidate = fragment
            }
            // Also keep deduplicated segment stream for engines that emit incremental chunks.
            if !assembledSegments.contains(fragment) {
                assembledSegments.append(fragment)
            }
            if result.isFinal {
                break
            }
        }

        var final = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if final.isEmpty, !assembledSegments.isEmpty {
            final = assembledSegments.joined(separator: " ")
                .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if !assembledSegments.isEmpty {
            let joined = assembledSegments.joined(separator: " ")
                .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if joined.count > final.count {
                final = joined
            }
        }
        guard !final.isEmpty else { throw ASRBackendError.emptyResult }
        return final
    }

    private func transcribeWithLegacySpeechRecognizer(_ audioURL: URL) async throws -> String {
        try await ensureLegacySpeechAuthorization()

        guard let recognizer = resolvedLegacySpeechRecognizer() else {
            throw ASRBackendError.unsupported("No SFSpeechRecognizer available for the current language settings.")
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        if #available(macOS 13.0, *) {
            request.requiresOnDeviceRecognition = true
        }

        let text = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            var settled = false
            var taskRef: SFSpeechRecognitionTask?
            taskRef = recognizer.recognitionTask(with: request) { result, error in
                if settled { return }

                if let error {
                    settled = true
                    taskRef?.cancel()
                    continuation.resume(throwing: ASRBackendError.transcriptionFailed(error.localizedDescription))
                    return
                }

                guard let result else { return }
                if result.isFinal {
                    settled = true
                    taskRef?.cancel()
                    let value = result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if value.isEmpty {
                        continuation.resume(throwing: ASRBackendError.emptyResult)
                    } else {
                        continuation.resume(returning: value)
                    }
                }
            }
        }

        return text
    }

    private func ensureLegacySpeechAuthorization() async throws {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current == .authorized { return }

        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard granted == .authorized else {
            throw ASRBackendError.unsupported("Speech recognition permission is not granted.")
        }
    }

    private func preferredLanguageIdentifier() -> String {
        let raw = AppState.shared.selectedLanguage.id.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "fr" : raw
    }

    private func preferredLocaleCandidates() -> [Locale] {
        let preferred = preferredLanguageIdentifier().lowercased()
        var ids: [String] = [preferred]

        switch preferred {
        case "fr":
            ids.append(contentsOf: ["fr-FR", "fr-CA"])
        case "en":
            ids.append(contentsOf: ["en-US", "en-GB"])
        case "es":
            ids.append(contentsOf: ["es-ES", "es-MX"])
        case "pt":
            ids.append(contentsOf: ["pt-PT", "pt-BR"])
        case "zh":
            ids.append(contentsOf: ["zh-CN", "zh-Hans-CN", "zh-TW"])
        case "yue":
            ids.append(contentsOf: ["yue-Hant-HK", "zh-HK"])
        case "ja":
            ids.append("ja-JP")
        case "de":
            ids.append("de-DE")
        case "it":
            ids.append("it-IT")
        case "ru":
            ids.append("ru-RU")
        default:
            break
        }

        ids.append(Locale.current.identifier)
        ids.append("en-US")

        var unique: [String] = []
        for id in ids where !id.isEmpty {
            if !unique.contains(where: { $0.caseInsensitiveCompare(id) == .orderedSame }) {
                unique.append(id)
            }
        }
        return unique.map(Locale.init(identifier:))
    }

    private static func languageCode(from localeIdentifier: String) -> String {
        let lowered = localeIdentifier.lowercased()
        let separators: Set<Character> = ["-", "_", "@", "."]
        let code = lowered.split(whereSeparator: { separators.contains($0) }).first.map(String.init) ?? lowered
        return code
    }

    @available(macOS 26.0, *)
    private func resolvedSpeechAnalyzerLocale() async -> Locale? {
        let supported = Array(await SpeechTranscriber.supportedLocales)
        guard !supported.isEmpty else { return nil }

        let candidates = preferredLocaleCandidates()
        for candidate in candidates {
            if let exact = supported.first(where: {
                $0.identifier.caseInsensitiveCompare(candidate.identifier) == .orderedSame
            }) {
                return exact
            }
        }

        for candidate in candidates {
            let wantedCode = Self.languageCode(from: candidate.identifier)
            if let byLanguage = supported.first(where: {
                Self.languageCode(from: $0.identifier) == wantedCode
            }) {
                return byLanguage
            }
        }

        return supported.first
    }

    private func resolvedLegacySpeechRecognizer() -> SFSpeechRecognizer? {
        let candidates = preferredLocaleCandidates()
        for candidate in candidates {
            if let recognizer = SFSpeechRecognizer(locale: candidate) {
                return recognizer
            }
        }
        return SFSpeechRecognizer(locale: Locale.current)
    }
}
