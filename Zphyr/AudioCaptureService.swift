//
//  AudioCaptureService.swift
//  Zphyr
//
//  Manages real-time audio capture from the microphone, resampling to 16 kHz
//  mono Float32 for ASR consumption.
//

import Foundation
@preconcurrency import AVFoundation
import Observation
import os

// MARK: - Thread-safe Audio Buffer

internal final class AudioSampleBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []

    enum AppendStatus {
        case appended
        case truncated
        case full
    }

    func reset() {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func reserveCapacity(_ capacity: Int) {
        guard capacity > 0 else { return }
        lock.lock()
        samples.reserveCapacity(capacity)
        lock.unlock()
    }

    func append(_ chunk: [Float], maxSamples: Int) -> AppendStatus {
        chunk.withUnsafeBufferPointer { pointer in
            append(pointer, maxSamples: maxSamples)
        }
    }

    func append(_ chunk: UnsafeBufferPointer<Float>, maxSamples: Int) -> AppendStatus {
        guard !chunk.isEmpty else { return .appended }
        lock.lock()
        defer { lock.unlock() }
        let remaining = max(0, maxSamples - samples.count)
        guard remaining > 0 else { return .full }
        if chunk.count <= remaining {
            samples.append(contentsOf: chunk)
            return .appended
        }
        let prefix = chunk.prefix(remaining)
        samples.append(contentsOf: prefix)
        return .truncated
    }

    func snapshot() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return samples.count
    }
}

// MARK: - Thread-safe Boolean Flag

internal final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(_ initialValue: Bool = false) {
        value = initialValue
    }

    func reset(to newValue: Bool = false) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func setIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !value else { return false }
        value = true
        return true
    }
}

// MARK: - Audio File Loading Errors

enum AudioFileLoadError: Error {
    case invalidBuffer
    case conversionFailed(String)
    case emptyAudio
}

// MARK: - AudioCaptureService

@Observable
@MainActor
final class AudioCaptureService {
    // TODO: [VAD_REALTIME] For sub-word latency, integrate WebRTC VAD C library here
    // to gate audio frames before they reach the buffer (energy-based gate only for now).

    /// Nonisolated constant — safe to access from any context including nonisolated static funcs.
    nonisolated static let sampleRate: Double = 16_000
    nonisolated static let maxDurationSeconds: Double = 300

    private(set) var sampleCount: Int = 0

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.zphyr",
        category: "AudioCapture"
    )

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private let sampleBuffer = AudioSampleBuffer()
    private let captureLimitFlag = LockedFlag()

    private var maxSamples: Int {
        Int(Self.sampleRate * Self.maxDurationSeconds)
    }

    // MARK: - Public API

    /// Starts capturing audio from the default input device, resampling to 16 kHz mono.
    /// - Parameter onLevels: Called on the main actor with an array of HUD level values (~28 bands)
    ///   at roughly 100 ms intervals for waveform visualization.
    /// - Parameter onAudioChunk: Optional callback receiving resampled 16 kHz mono chunks.
    ///   Used to prepare future streaming / partial transcription paths.
    /// - Returns: `true` if capture started successfully, `false` on failure.
    @discardableResult
    func startCapture(
        onLevels: @escaping ([Float]) -> Void,
        onAudioChunk: (([Float]) -> Void)? = nil
    ) -> Bool {
        // Always tear down any previous engine (safety net for race conditions).
        stopCapture()

        sampleBuffer.reset()
        let preallocatedSamples = min(maxSamples, Int(Self.sampleRate * 120))
        sampleBuffer.reserveCapacity(preallocatedSamples)
        captureLimitFlag.reset()

        let engine = AVAudioEngine()
        audioEngine = engine

        let input = engine.inputNode
        self.inputNode = input

        // Native hardware format (e.g. 44100 or 48000 Hz, possibly multi-channel)
        let hwFormat = input.outputFormat(forBus: 0)

        // Target format: 16 kHz, mono, Float32 — expected by ASR
        guard let whisperFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            Self.logger.error("Unable to create 16kHz audio format.")
            return false
        }

        // Build a converter from hardware format -> 16kHz mono
        guard let converter = AVAudioConverter(from: hwFormat, to: whisperFormat) else {
            Self.logger.error("Unable to create audio converter.")
            return false
        }

        let resamplingRatio = Self.sampleRate / hwFormat.sampleRate
        let captureMaxSamples = maxSamples
        let captureMaxDuration = Self.maxDurationSeconds
        let buffer = sampleBuffer
        let limitFlag = captureLimitFlag
        let reusableCapacity = AVAudioFrameCount(Double(4096) * resamplingRatio + 8)
        guard let reusableOutBuffer = AVAudioPCMBuffer(pcmFormat: whisperFormat, frameCapacity: reusableCapacity) else {
            Self.logger.error("Unable to initialize audio buffer.")
            return false
        }

        // Tap on the hardware format, convert each buffer to 16kHz
        var lastHUDLevelPushAt = CFAbsoluteTimeGetCurrent()
        var hudLevels = [Float](repeating: 0.1, count: 28)
        input.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [buffer, limitFlag] hwBuffer, _ in
            autoreleasepool {
                // TODO: [STREAMING] For live corrections, emit partial buffers here at regular intervals
                // instead of waiting for stopCapture(). Plug StreamingASRSession here.

                // Compute how many output frames correspond to this input buffer
                let inputFrames = AVAudioFrameCount(hwBuffer.frameLength)
                let outputFrames = AVAudioFrameCount(Double(inputFrames) * resamplingRatio + 1)
                let outBuffer: AVAudioPCMBuffer
                if outputFrames <= reusableOutBuffer.frameCapacity {
                    reusableOutBuffer.frameLength = 0
                    outBuffer = reusableOutBuffer
                } else {
                    guard let fallbackBuffer = AVAudioPCMBuffer(pcmFormat: whisperFormat, frameCapacity: outputFrames) else { return }
                    outBuffer = fallbackBuffer
                }

                var conversionError: NSError?
                var consumed = false
                let status = converter.convert(to: outBuffer, error: &conversionError) { _, outStatus in
                    if consumed {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    consumed = true
                    outStatus.pointee = .haveData
                    return hwBuffer
                }

                guard status != .error, let channelData = outBuffer.floatChannelData?[0] else { return }
                let frameCount = Int(outBuffer.frameLength)
                guard frameCount > 0 else { return }
                let samplePointer = UnsafeBufferPointer(start: channelData, count: frameCount)
                let appendStatus = buffer.append(samplePointer, maxSamples: captureMaxSamples)
                let chunk = Array(samplePointer)
                onAudioChunk?(chunk)
                if appendStatus != .appended && limitFlag.setIfNeeded() {
                    if appendStatus == .truncated {
                        AudioCaptureService.logger.warning("[AudioCapture] reached max duration (\(Int(captureMaxDuration), privacy: .public)s); truncating additional samples")
                    } else {
                        AudioCaptureService.logger.warning("[AudioCapture] reached max duration (\(Int(captureMaxDuration), privacy: .public)s); dropping additional samples")
                    }
                }

                // RMS spectrum for HUD (computed on the original hwBuffer for responsiveness)
                let now = CFAbsoluteTimeGetCurrent()
                guard now - lastHUDLevelPushAt >= 0.10 else { return }
                lastHUDLevelPushAt = now

                guard let hwChannel = hwBuffer.floatChannelData?[0] else { return }
                let hwFrames = Int(hwBuffer.frameLength)
                guard hwFrames > 0 else { return }
                let bandCount = hudLevels.count
                let bandSize = max(1, hwFrames / bandCount)
                for i in 0..<bandCount {
                    let start = i * bandSize
                    let end = min(start + bandSize, hwFrames)
                    guard start < end else {
                        hudLevels[i] = 0.1
                        continue
                    }
                    let slice = UnsafeBufferPointer(start: hwChannel + start, count: end - start)
                    var peak: Float = 0
                    for sample in slice {
                        peak = max(peak, abs(sample))
                    }
                    hudLevels[i] = min(1.0, sqrt(min(1.0, peak * 18)))
                }
                let levels = hudLevels
                Task { @MainActor in
                    onLevels(levels)
                }
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            Self.logger.error("Audio engine start failed: \(error.localizedDescription)")
            stopCapture()
            return false
        }
        sampleCount = 0
        return true
    }

    /// Stops audio capture and tears down the engine.
    func stopCapture() {
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        sampleCount = sampleBuffer.count()
    }

    /// Returns a snapshot of all captured samples (thread-safe copy).
    func snapshotSamples() -> [Float] {
        sampleBuffer.snapshot()
    }

    /// Resets the sample buffer, discarding all captured audio.
    func resetBuffer() {
        sampleBuffer.reset()
        captureLimitFlag.reset()
        sampleCount = 0
    }

    // MARK: - Audio File Loading

    /// Loads an audio file and resamples it to 16 kHz mono Float32 PCM.
    nonisolated static func loadAudioFile(at url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inputFormat = file.processingFormat

        guard file.length > 0 else {
            throw AudioFileLoadError.emptyAudio
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioFileLoadError.invalidBuffer
        }

        let inputFrameCount = AVAudioFrameCount(file.length)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: inputFrameCount) else {
            throw AudioFileLoadError.invalidBuffer
        }
        try file.read(into: inputBuffer)

        if inputFormat.sampleRate == sampleRate,
           inputFormat.channelCount == 1,
           inputFormat.commonFormat == .pcmFormatFloat32,
           let channelData = inputBuffer.floatChannelData?[0] {
            let frameCount = Int(inputBuffer.frameLength)
            guard frameCount > 0 else {
                throw AudioFileLoadError.emptyAudio
            }
            return Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioFileLoadError.conversionFailed("converter unavailable")
        }

        let ratio = sampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio + 1024)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
            throw AudioFileLoadError.invalidBuffer
        }

        var conversionError: NSError?
        var didConsumeInput = false
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if didConsumeInput {
                outStatus.pointee = .endOfStream
                return nil
            }
            didConsumeInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error else {
            throw AudioFileLoadError.conversionFailed(conversionError?.localizedDescription ?? "conversion error")
        }
        guard let outputData = outputBuffer.floatChannelData?[0] else {
            throw AudioFileLoadError.invalidBuffer
        }
        let outputFrameCount = Int(outputBuffer.frameLength)
        guard outputFrameCount > 0 else {
            throw AudioFileLoadError.emptyAudio
        }
        return Array(UnsafeBufferPointer(start: outputData, count: outputFrameCount))
    }
}
