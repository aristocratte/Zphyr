import AVFoundation
import Darwin
import Foundation
import os

@MainActor
final class CodexVoiceBackend: ASRService {
    static let shared = CodexVoiceBackend()
    nonisolated static let maxUploadSegmentDurationSeconds: TimeInterval = 8.0

    private let authService = CodexVoiceAuthService()
    private lazy var transcriptionService = CodexVoiceTranscriptionService(authService: authService)
    private let log = Logger(subsystem: "com.zphyr.app", category: "CodexVoiceASR")

    let descriptor = ASRBackendCatalog.descriptor(for: .codexVoice)
    private(set) var isLoaded: Bool = CodexVoiceAuthService.hasReadableCredentials()
    private(set) var installError: String?

    private init() {}

    nonisolated static var authFileURL: URL {
        CodexVoiceAuthService.defaultAuthFileURL
    }

    nonisolated static func hasReadableCredentials() -> Bool {
        CodexVoiceAuthService.hasReadableCredentials()
    }

    func loadIfInstalled() async {
        do {
            _ = try await authService.currentCredentials()
            installError = nil
            isLoaded = true
        } catch {
            installError = error.localizedDescription
            isLoaded = false
        }
    }

    func transcribe(audioBuffer: [Float]) async throws -> String {
        guard !audioBuffer.isEmpty else { throw ASRBackendError.invalidAudioBuffer }

        let recording = try Self.writeTemporaryWAV(from: audioBuffer)
        defer { try? FileManager.default.removeItem(at: recording.url) }

        do {
            let text = try await transcriptionService.transcribe(recording)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw ASRBackendError.emptyResult }
            log.notice("[CodexVoiceASR] transcribed \(text.count, privacy: .public) chars")
            return text
        } catch {
            installError = error.localizedDescription
            throw error
        }
    }

    private nonisolated static func writeTemporaryWAV(from samples: [Float]) throws -> CodexVoiceRecordedAudio {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioCaptureService.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw ASRBackendError.invalidAudioBuffer
        }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw ASRBackendError.invalidAudioBuffer
        }
        pcm.frameLength = frameCount

        guard let channelData = pcm.floatChannelData?[0] else {
            throw ASRBackendError.invalidAudioBuffer
        }
        samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            channelData.update(from: base, count: samples.count)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zphyr-codex-voice-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: pcm)

        return CodexVoiceRecordedAudio(
            url: url,
            contentType: "audio/wav",
            filename: url.lastPathComponent
        )
    }
}

nonisolated private struct CodexVoiceRecordedAudio: Sendable {
    let url: URL
    let contentType: String
    let filename: String
}

nonisolated private struct CodexVoiceCredentials: Sendable {
    let accessToken: String
    let accountID: String
}

nonisolated private struct CodexVoiceAuthFile: Decodable {
    struct Tokens: Decodable {
        let access_token: String
        let account_id: String
    }

    let tokens: Tokens
}

nonisolated private enum CodexVoiceAuthError: LocalizedError {
    case authFileMissing
    case credentialsUnavailable
    case refreshFailed(String)

    var errorDescription: String? {
        switch self {
        case .authFileMissing:
            return "Codex auth could not be found. Sign in to Codex first."
        case .credentialsUnavailable:
            return "Codex auth is incomplete. Sign in to Codex again."
        case .refreshFailed(let message):
            return "Codex auth refresh failed: \(message)"
        }
    }
}

private actor CodexVoiceAuthService {
    nonisolated static let defaultAuthFileURL = URL(
        fileURLWithPath: NSString(string: "~/.codex/auth.json").expandingTildeInPath
    )

    private let authFileURL: URL
    private let codexBinaryResolver: @Sendable () -> String?

    init(
        authFileURL: URL = CodexVoiceAuthService.defaultAuthFileURL,
        codexBinaryResolver: @escaping @Sendable () -> String? = CodexVoiceAuthService.defaultCodexBinaryResolver
    ) {
        self.authFileURL = authFileURL
        self.codexBinaryResolver = codexBinaryResolver
    }

    nonisolated static func hasReadableCredentials(
        at authFileURL: URL = CodexVoiceAuthService.defaultAuthFileURL
    ) -> Bool {
        guard let data = try? Data(contentsOf: authFileURL),
              let authFile = try? JSONDecoder().decode(CodexVoiceAuthFile.self, from: data) else {
            return false
        }
        return !authFile.tokens.access_token.isEmpty && !authFile.tokens.account_id.isEmpty
    }

    func currentCredentials() throws -> CodexVoiceCredentials {
        try readCredentials()
    }

    func refreshCredentials() async throws -> CodexVoiceCredentials {
        try await refreshAuthState()
        return try readCredentials()
    }

    private func readCredentials() throws -> CodexVoiceCredentials {
        guard FileManager.default.fileExists(atPath: authFileURL.path) else {
            throw CodexVoiceAuthError.authFileMissing
        }

        let data = try Data(contentsOf: authFileURL)
        let authFile = try JSONDecoder().decode(CodexVoiceAuthFile.self, from: data)

        guard !authFile.tokens.access_token.isEmpty, !authFile.tokens.account_id.isEmpty else {
            throw CodexVoiceAuthError.credentialsUnavailable
        }

        return CodexVoiceCredentials(
            accessToken: authFile.tokens.access_token,
            accountID: authFile.tokens.account_id
        )
    }

    private func refreshAuthState() async throws {
        let codexBinaryURL = try resolveCodexBinaryURL()

        guard FileManager.default.isExecutableFile(atPath: codexBinaryURL.path) else {
            throw CodexVoiceAuthError.refreshFailed("Codex CLI was not found at \(codexBinaryURL.path).")
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = codexBinaryURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        let messages: [[String: Any]] = [
            [
                "id": 1,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "zphyr-codex-voice",
                        "version": "0.1.0",
                    ],
                    "capabilities": [
                        "experimentalApi": true,
                        "optOutNotificationMethods": [],
                    ],
                ],
            ],
            [
                "id": 2,
                "method": "account/read",
                "params": [
                    "refreshToken": true,
                ],
            ],
        ]

        for message in messages {
            let data = try JSONSerialization.data(withJSONObject: message)
            inputPipe.fileHandleForWriting.write(data)
            inputPipe.fileHandleForWriting.write(Data([0x0A]))
        }

        try inputPipe.fileHandleForWriting.close()

        let stdoutData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw CodexVoiceAuthError.refreshFailed(
                message?.isEmpty == false
                    ? message!
                    : "The Codex app-server exited with status \(process.terminationStatus)."
            )
        }

        let output = String(decoding: stdoutData, as: UTF8.self)
        let lines = output.split(whereSeparator: \.isNewline)
        guard lines.contains(where: { $0.contains("\"id\":2") && $0.contains("\"result\"") }) else {
            throw CodexVoiceAuthError.refreshFailed("Codex did not confirm the auth refresh request.")
        }
    }

    private func resolveCodexBinaryURL() throws -> URL {
        guard let executablePath = codexBinaryResolver(),
              FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw CodexVoiceAuthError.refreshFailed(
                """
                Codex CLI could not be found. Install Codex, make `codex` available on your PATH, \
                or set CODEX_CLI_PATH to the executable location.
                """
            )
        }

        return URL(fileURLWithPath: executablePath)
    }

    private nonisolated static func defaultCodexBinaryPath() -> String? {
        let candidatePaths = [
            ProcessInfo.processInfo.environment["CODEX_CLI_PATH"],
            codexBinaryPathFromPATH(),
            "/Applications/Codex.app/Contents/Resources/codex",
        ].compactMap { $0 }

        return candidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    private nonisolated static let defaultCodexBinaryResolver: @Sendable () -> String? = {
        CodexVoiceAuthService.defaultCodexBinaryPath()
    }

    private nonisolated static func codexBinaryPathFromPATH() -> String? {
        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["codex"]
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return nil
        }

        let path = String(decoding: output, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}

nonisolated private enum CodexVoiceTranscriptionError: LocalizedError {
    case invalidResponse
    case unauthorized
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Codex returned an invalid transcription response."
        case .unauthorized:
            return "Codex auth expired. Open Codex and sign in again."
        case .serverError(let message):
            return "Codex transcription failed: \(message)"
        }
    }
}

private actor CodexVoiceTranscriptionService {
    private struct TranscriptionResponse: Decodable {
        let text: String
    }

    private let authService: CodexVoiceAuthService
    private let endpoint = URL(string: "https://chatgpt.com/backend-api/transcribe")!
    private let segmenter = CodexVoiceTranscriptionSegmenter(
        maxSegmentDuration: CodexVoiceBackend.maxUploadSegmentDurationSeconds
    )

    init(authService: CodexVoiceAuthService) {
        self.authService = authService
    }

    func transcribe(_ recording: CodexVoiceRecordedAudio) async throws -> String {
        let segments = try segmenter.segments(for: recording)
        defer {
            for segment in segments where segment.url != recording.url {
                try? FileManager.default.removeItem(at: segment.url)
            }
        }

        var credentials = try await authService.currentCredentials()
        var transcripts: [String] = []
        for segment in segments {
            let transcript: String
            do {
                transcript = try await performTranscription(segment, credentials: credentials)
            } catch CodexVoiceTranscriptionError.unauthorized {
                credentials = try await authService.refreshCredentials()
                transcript = try await performTranscription(segment, credentials: credentials)
            }
            transcripts.append(transcript)
        }

        return transcripts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func performTranscription(
        _ recording: CodexVoiceRecordedAudio,
        credentials: CodexVoiceCredentials
    ) async throws -> String {
        let boundary = "----zphyr-codex-voice-\(UUID().uuidString)"
        let body = try makeMultipartBody(recording: recording, boundary: boundary)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 60
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
        request.setValue(codexDesktopUserAgent(), forHTTPHeaderField: "User-Agent")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodexVoiceTranscriptionError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw CodexVoiceTranscriptionError.unauthorized
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw CodexVoiceTranscriptionError.serverError(
                message?.isEmpty == false ? message! : "HTTP \(httpResponse.statusCode)"
            )
        }

        if let decoded = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) {
            return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = object["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        throw CodexVoiceTranscriptionError.invalidResponse
    }

    private func makeMultipartBody(recording: CodexVoiceRecordedAudio, boundary: String) throws -> Data {
        var body = Data()
        let fileData = try Data(contentsOf: recording.url)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(recording.filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(recording.contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return body
    }

    private func codexDesktopUserAgent() -> String {
        let codexBundleURL = URL(fileURLWithPath: "/Applications/Codex.app")
        let codexBundle = Bundle(url: codexBundleURL)
        let version = codexBundle?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let osString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        let arch = ProcessInfo.processInfo.machineHardwareName ?? "arm64"
        return "Codex Desktop/\(version) (Mac OS \(osString); \(arch))"
    }
}

nonisolated private struct CodexVoiceAudioRecordingMetadata {
    let duration: TimeInterval

    init(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let sampleRate = file.processingFormat.sampleRate
        duration = sampleRate > 0 ? Double(file.length) / sampleRate : 0
    }
}

nonisolated private struct CodexVoiceTranscriptionSegmenter {
    let maxSegmentDuration: TimeInterval

    func segments(for recording: CodexVoiceRecordedAudio) throws -> [CodexVoiceRecordedAudio] {
        let metadata = try CodexVoiceAudioRecordingMetadata(url: recording.url)
        guard metadata.duration > maxSegmentDuration else {
            return [recording]
        }

        let inputFile = try AVAudioFile(forReading: recording.url)
        let sampleRate = inputFile.processingFormat.sampleRate
        guard sampleRate > 0 else {
            return [recording]
        }

        let framesPerSegment = AVAudioFramePosition(maxSegmentDuration * sampleRate)
        guard framesPerSegment > 0 else {
            return [recording]
        }

        var segments: [CodexVoiceRecordedAudio] = []
        while inputFile.framePosition < inputFile.length {
            let remainingFrames = inputFile.length - inputFile.framePosition
            let framesToRead = min(framesPerSegment, remainingFrames)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: inputFile.processingFormat,
                frameCapacity: AVAudioFrameCount(framesToRead)
            ) else {
                throw CodexVoiceTranscriptionError.invalidResponse
            }

            try inputFile.read(into: buffer, frameCount: AVAudioFrameCount(framesToRead))
            guard buffer.frameLength > 0 else {
                break
            }

            let segmentURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("zphyr-codex-voice-segment-\(UUID().uuidString)")
                .appendingPathExtension("wav")
            let outputFile = try AVAudioFile(forWriting: segmentURL, settings: inputFile.fileFormat.settings)
            try outputFile.write(from: buffer)

            segments.append(CodexVoiceRecordedAudio(
                url: segmentURL,
                contentType: recording.contentType,
                filename: segmentURL.lastPathComponent
            ))
        }

        return segments.isEmpty ? [recording] : segments
    }
}

private extension ProcessInfo {
    nonisolated var machineHardwareName: String? {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &buffer, &size, nil, 0)
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
