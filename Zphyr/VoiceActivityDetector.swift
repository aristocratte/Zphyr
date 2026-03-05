import Foundation

enum VoiceActivityDetectionError: LocalizedError {
    case emptyBuffer
    case noVoiceDetected
    case insufficientVoice

    var errorDescription: String? {
        switch self {
        case .emptyBuffer:
            return "Audio buffer is empty."
        case .noVoiceDetected:
            return "No voice activity detected in the audio buffer."
        case .insufficientVoice:
            return "Detected voice segment is too short."
        }
    }
}

struct VoiceActivityDetectionResult: Sendable {
    let trimmedBuffer: [Float]
    let leadingTrimmedSamples: Int
    let trailingTrimmedSamples: Int
    let threshold: Float
}

/// Basic RMS VAD used to trim long start/end silences before ASR.
struct VoiceActivityDetector {
    var sampleRate: Double = 16_000
    var frameDurationMs: Double = 20
    var trimSilenceThresholdMs: Double = 400
    var minVoiceDurationMs: Double = 120

    func trim(_ buffer: [Float]) throws -> VoiceActivityDetectionResult {
        guard !buffer.isEmpty else { throw VoiceActivityDetectionError.emptyBuffer }

        let frameSize = max(1, Int(sampleRate * frameDurationMs / 1_000))
        let frameCount = Int(ceil(Double(buffer.count) / Double(frameSize)))
        guard frameCount > 0 else { throw VoiceActivityDetectionError.emptyBuffer }

        var rmsValues: [Float] = []
        rmsValues.reserveCapacity(frameCount)

        for frameIndex in 0..<frameCount {
            let start = frameIndex * frameSize
            let end = min(buffer.count, start + frameSize)
            guard start < end else {
                rmsValues.append(0)
                continue
            }

            var energy: Float = 0
            for i in start..<end {
                let s = buffer[i]
                energy += s * s
            }
            let rms = sqrt(energy / Float(end - start))
            rmsValues.append(rms)
        }

        let sortedRMS = rmsValues.sorted()
        let floorIndex = min(max(0, Int(Double(sortedRMS.count) * 0.2)), max(0, sortedRMS.count - 1))
        let noiseFloor = sortedRMS.isEmpty ? 0 : sortedRMS[floorIndex]
        let peak = rmsValues.max() ?? 0
        let adaptiveThreshold = max(0.0012, noiseFloor * 2.2, peak * 0.05)

        guard let firstVoiceFrame = rmsValues.firstIndex(where: { $0 >= adaptiveThreshold }),
              let lastVoiceFrame = rmsValues.lastIndex(where: { $0 >= adaptiveThreshold }) else {
            // If the signal has some energy but never crosses the adaptive threshold,
            // keep the raw buffer instead of hard-failing (prevents false negatives on low-gain mics).
            if peak >= 0.0018 {
                let minVoiceSamples = Int(sampleRate * (minVoiceDurationMs / 1_000))
                guard buffer.count >= minVoiceSamples else {
                    throw VoiceActivityDetectionError.insufficientVoice
                }
                return VoiceActivityDetectionResult(
                    trimmedBuffer: buffer,
                    leadingTrimmedSamples: 0,
                    trailingTrimmedSamples: 0,
                    threshold: adaptiveThreshold
                )
            }
            throw VoiceActivityDetectionError.noVoiceDetected
        }

        let requiredSilenceFrames = Int(ceil(trimSilenceThresholdMs / frameDurationMs))

        let leadingSilenceFrames = firstVoiceFrame
        let trailingSilenceFrames = max(0, (rmsValues.count - 1) - lastVoiceFrame)

        let trimLeading = leadingSilenceFrames >= requiredSilenceFrames
        let trimTrailing = trailingSilenceFrames >= requiredSilenceFrames

        let startSample = trimLeading ? firstVoiceFrame * frameSize : 0
        let endSampleExclusive = trimTrailing ? min(buffer.count, (lastVoiceFrame + 1) * frameSize) : buffer.count

        guard startSample < endSampleExclusive else {
            throw VoiceActivityDetectionError.noVoiceDetected
        }

        let trimmed: [Float]
        if startSample == 0 && endSampleExclusive == buffer.count {
            // Fast path: no trim required, keep original buffer to avoid a full copy.
            trimmed = buffer
        } else {
            trimmed = Array(buffer[startSample..<endSampleExclusive])
        }

        let minVoiceSamples = Int(sampleRate * (minVoiceDurationMs / 1_000))
        guard trimmed.count >= minVoiceSamples else {
            throw VoiceActivityDetectionError.insufficientVoice
        }

        return VoiceActivityDetectionResult(
            trimmedBuffer: trimmed,
            leadingTrimmedSamples: startSample,
            trailingTrimmedSamples: max(0, buffer.count - endSampleExclusive),
            threshold: adaptiveThreshold
        )
    }
}
