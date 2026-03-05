//
//  Qwen3ASREngine.swift
//  Zphyr
//
//  On-device ASR engine using Qwen3-ASR-1.7B (MLX 8-bit).
//  Model : aufklarer/Qwen3-ASR-1.7B-MLX-8bit  (~2.46 GB)
//  Audio : 128-mel spectrogram at 16 kHz  →  tokens  →  text
//
//  ─── HOW TO ENABLE ───────────────────────────────────────────────────────────
//  Xcode → Target "Zphyr" → Build Phases → Link Binary With Libraries
//  Add: MLX   MLXNN   MLXFast   (from the mlx-swift package already in SPM)
//  Without that linkage the #else stub is used and ASR remains unavailable.
//  ─────────────────────────────────────────────────────────────────────────────

import Foundation
import Accelerate
import os

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Active implementation (when MLX is linked to the target)
// ═══════════════════════════════════════════════════════════════════════════════
#if canImport(MLX) && canImport(MLXNN)
import MLX
import MLXNN

// MARK: - Mel Spectrogram Extractor

/// Computes a 128-bin log-mel spectrogram from 16 kHz mono Float32 samples.
/// Window: 25 ms (400 samples), Hop: 10 ms (160 samples), 128 mel bins.
private enum MelSpec {
    static let sampleRate = 16_000
    static let nFFT       = 400         // 25 ms window at 16 kHz
    static let hopLength  = 160         // 10 ms hop  at 16 kHz
    static let nMels      = 128
    static let fMin: Double = 0.0
    static let fMax: Double = 8_000.0

    // Precomputed filterbank — computed once on first access.
    private static let _filterbank: [[Float]] = buildMelFilterbank()

    /// Returns [nFrames × nMels] as an MLXArray of shape [nFrames, 128].
    static func compute(samples: [Float]) -> MLXArray {
        let n = samples.count
        guard n >= nFFT else { return MLXArray.zeros([1, nMels]) }
        let numFrames = (n - nFFT) / hopLength + 1

        // Hann window
        let hann: [Float] = (0..<nFFT).map { i in
            0.5 * (1.0 - cos(2.0 * Float.pi * Float(i) / Float(nFFT - 1)))
        }

        let log2n = vDSP_Length(log2(Double(nFFT)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return MLXArray.zeros([numFrames, nMels])
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var spectrogram = [Float](repeating: 0.0, count: numFrames * nMels)
        let binCount = nFFT / 2 + 1
        let fb = _filterbank

        for f in 0..<numFrames {
            let start = f * hopLength
            var frame = [Float](repeating: 0.0, count: nFFT)
            let end = min(start + nFFT, n)
            for i in start..<end { frame[i - start] = samples[i] }

            // Apply Hann window
            vDSP_vmul(frame, 1, hann, 1, &frame, 1, vDSP_Length(nFFT))

            // In-place real FFT
            var re = frame
            var im = [Float](repeating: 0.0, count: nFFT)
            re.withUnsafeMutableBufferPointer { rp in
                im.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    vDSP_fft_zrip(fftSetup, &split, 1, log2n, Int32(FFT_FORWARD))
                }
            }

            // Power spectrum (normalised)
            var power = [Float](repeating: 0.0, count: binCount)
            let scale = 1.0 / Float(nFFT)
            power[0] = (re[0] * scale) * (re[0] * scale)
            for k in 1..<(nFFT / 2) {
                let r = re[k] * scale
                let i = im[k] * scale
                power[k] = r * r + i * i
            }
            // Nyquist bin: stored in re[0] after vDSP_fft_zrip (DC), use imaginary
            power[nFFT / 2] = (im[0] * scale) * (im[0] * scale)

            // Apply mel filterbank → log energy
            for m in 0..<nMels {
                var energy: Float = 0.0
                let row = fb[m]
                for k in 0..<min(row.count, binCount) {
                    energy += row[k] * power[k]
                }
                spectrogram[f * nMels + m] = log(max(energy, 1e-10))
            }
        }
        return MLXArray(spectrogram, [numFrames, nMels])
    }

    private static func buildMelFilterbank() -> [[Float]] {
        func hzToMel(_ hz: Double) -> Double { 2595.0 * log10(1.0 + hz / 700.0) }
        func melToHz(_ mel: Double) -> Double { 700.0 * (pow(10.0, mel / 2595.0) - 1.0) }

        let minMel = hzToMel(fMin)
        let maxMel = hzToMel(fMax)
        let numBins = nFFT / 2 + 1
        let freqPerBin = Double(sampleRate) / Double(nFFT)

        // nMels + 2 evenly spaced mel-scale points
        let melPts = (0...nMels + 1).map { i -> Double in
            melToHz(minMel + Double(i) * (maxMel - minMel) / Double(nMels + 1))
        }

        return (0..<nMels).map { m -> [Float] in
            var row = [Float](repeating: 0.0, count: numBins)
            let lo = melPts[m]; let ctr = melPts[m + 1]; let hi = melPts[m + 2]
            for k in 0..<numBins {
                let hz = Double(k) * freqPerBin
                if hz >= lo && hz <= ctr      { row[k] = Float((hz - lo) / (ctr - lo)) }
                else if hz > ctr && hz <= hi  { row[k] = Float((hi - hz) / (hi - ctr)) }
            }
            return row
        }
    }
}

// MARK: - Quantization Helpers

private let qGroupSize = 64
private let qBits = 8

/// Returns quantization companion keys (`scales`/`biases`) for a weight key.
/// Supports both naming styles:
/// - `<prefix>.weight` + companions at `<prefix>.scales`
/// - legacy companions at `<prefix>.weight.scales`
private func quantizedCompanionKeyCandidates(for weightKey: String) -> [(scales: String, biases: String)] {
    if weightKey.hasSuffix(".weight") {
        let base = String(weightKey.dropLast(".weight".count))
        return [
            (base + ".scales", base + ".biases"),
            (weightKey + ".scales", weightKey + ".biases"),
        ]
    }
    return [
        (weightKey + ".scales", weightKey + ".biases"),
        (weightKey + ".weight.scales", weightKey + ".weight.biases"),
    ]
}

private func quantizedCompanions(
    for weightKey: String,
    in wts: [String: MLXArray]
) -> (scales: MLXArray, biases: MLXArray?)? {
    for keys in quantizedCompanionKeyCandidates(for: weightKey) {
        if let scales = wts[keys.scales] {
            return (scales, wts[keys.biases])
        }
    }
    return nil
}

/// Linear projection with support for packed MLX quantized weights.
/// - Expects `x` shape `[N, inFeatures]`.
private func linear(
    _ x: MLXArray,
    wts: [String: MLXArray],
    weightKey: String,
    biasKey: String? = nil
) -> MLXArray? {
    guard let w = wts[weightKey] else { return nil }
    let y: MLXArray
    if let companions = quantizedCompanions(for: weightKey, in: wts) {
        y = quantizedMM(
            x.asType(.float32),
            w,
            scales: companions.scales,
            biases: companions.biases,
            transpose: true,
            groupSize: qGroupSize,
            bits: qBits,
            mode: .affine
        )
    } else {
        guard x.shape.count >= 2, w.shape.count >= 2, x.shape[1] == w.shape[1] else {
            return nil
        }
        y = matmul(x.asType(.float32), w.asType(.float32).T)
    }
    if let biasKey, let bias = wts[biasKey]?.asType(.float32) {
        return y + bias.expandedDimensions(axis: 0)
    }
    return y
}

/// Embedding lookup with support for packed MLX quantized embedding tables.
private func tokenEmbedding(
    _ tokenId: Int,
    wts: [String: MLXArray],
    tableKey: String
) -> MLXArray? {
    guard let table = wts[tableKey] else { return nil }
    if let companions = quantizedCompanions(for: tableKey, in: wts) {
        let rowW = table[tokenId].expandedDimensions(axis: 0)
        let rowS = companions.scales[tokenId].expandedDimensions(axis: 0)
        let rowB = companions.biases?[tokenId].expandedDimensions(axis: 0)
        return dequantized(
            rowW,
            scales: rowS,
            biases: rowB,
            groupSize: qGroupSize,
            bits: qBits,
            mode: .affine
        ).asType(.float32)
    }
    return table[tokenId].expandedDimensions(axis: 0).asType(.float32)
}

/// Vocabulary projection with tied-weights fallback (`embed_tokens`) when `lm_head` is absent.
private func projectToVocabulary(_ x: MLXArray, wts: [String: MLXArray]) -> MLXArray? {
    if wts["lm_head.weight"] != nil {
        return linear(x, wts: wts, weightKey: "lm_head.weight")
    }
    guard let embed = wts["model.embed_tokens.weight"] else { return nil }
    if let companions = quantizedCompanions(for: "model.embed_tokens.weight", in: wts) {
        return quantizedMM(
            x.asType(.float32),
            embed,
            scales: companions.scales,
            biases: companions.biases,
            transpose: true,
            groupSize: qGroupSize,
            bits: qBits,
            mode: .affine
        )
    }
    guard x.shape.count >= 2, embed.shape.count >= 2, x.shape[1] == embed.shape[1] else {
        return nil
    }
    return matmul(x.asType(.float32), embed.asType(.float32).T)
}

private func audioFeatLengthAfterConv(_ inputLength: Int) -> Int {
    let remainder = inputLength % 100
    let featLen = max(0, (remainder - 1) / 2 + 1)
    return max(0, ((featLen - 1) / 2 + 1 - 1) / 2 + 1 + (inputLength / 100) * 13)
}

private func sinusoidPositionEmbedding(length: Int, channels: Int, maxTimescale: Float = 10_000) -> MLXArray {
    guard channels > 0, channels % 2 == 0 else {
        return MLXArray.zeros([max(1, length), max(1, channels)])
    }
    let half = channels / 2
    if half <= 1 {
        return MLXArray.zeros([max(1, length), channels])
    }
    let logTimescaleIncrement = log(Double(maxTimescale)) / Double(half - 1)
    let invTimescales: [Float] = (0..<half).map { idx in
        exp(Float(-logTimescaleIncrement * Double(idx)))
    }
    let time = MLXArray((0..<max(1, length)).map(Float.init), [max(1, length), 1])
    let inv = MLXArray(invTimescales, [1, half])
    let scaled = time * inv
    return concatenated([sin(scaled), cos(scaled)], axis: 1)
}

// MARK: - Activation functions (inline)

private func geluApprox(_ x: MLXArray) -> MLXArray {
    // Tanh approximation: 0.5 * x * (1 + tanh(√(2/π) * (x + 0.044715 x³)))
    0.5 * x * (1.0 + tanh(0.7978845608028654 * (x + 0.044715 * x * x * x)))
}

private func siluActivation(_ x: MLXArray) -> MLXArray {
    x * sigmoid(x)
}

// MARK: - Norms

private func rmsNorm(_ x: MLXArray, weight w: MLXArray, eps: Float = 1e-6) -> MLXArray {
    let rms = sqrt((x * x).mean(axis: -1, keepDims: true) + eps)
    return x / rms * w.asType(.float32)
}

private func layerNorm(_ x: MLXArray, w: MLXArray, b: MLXArray, eps: Float = 1e-5) -> MLXArray {
    let mean = x.mean(axis: -1, keepDims: true)
    let diff = x - mean
    let variance = (diff * diff).mean(axis: -1, keepDims: true)
    return diff / sqrt(variance + eps) * w.asType(.float32) + b.asType(.float32)
}

// MARK: - RoPE

/// Apply Rotary Position Embeddings.  x: [seq, heads, headDim]
private func applyRoPE(_ x: MLXArray, positions: MLXArray, theta: Float = 10_000.0) -> MLXArray {
    let headDim = x.shape[2]
    let half    = headDim / 2
    let inv_freq: [Float] = (0..<half).map { i in
        1.0 / pow(theta, Float(2 * i) / Float(headDim))
    }
    let freq = MLXArray(inv_freq, [half])                         // [half]
    let pos  = positions.asType(.float32).expandedDimensions(axis: 1) // [seq, 1]
    let ang  = (pos * freq.expandedDimensions(axis: 0))          // [seq, half]
    let cosA = cos(ang).expandedDimensions(axis: 1)              // [seq, 1, half]
    let sinA = sin(ang).expandedDimensions(axis: 1)

    let x1 = x[0..., 0..., ..<half]
    let x2 = x[0..., 0..., half...]
    let rot = concatenated([-x2, x1], axis: -1)                  // [seq, heads, headDim]
    let cosE = concatenated([cosA, cosA], axis: -1)              // [seq, 1, headDim]
    let sinE = concatenated([sinA, sinA], axis: -1)
    return x * cosE + rot * sinE
}

// MARK: - KV Cache

private struct KVEntry {
    var k: MLXArray
    var v: MLXArray
}

// MARK: - Audio Encoder (`audio_tower`, Qwen3-ASR)

/// One encoder transformer block.
private func audioEncoderBlock(
    _ x: MLXArray,
    wts: [String: MLXArray],
    pfx: String,
    dModel: Int,
    numHeads: Int
) -> MLXArray {
    let headDim = dModel / numHeads
    let seq     = x.shape[0]

    guard
        let ln1W = wts["\(pfx).self_attn_layer_norm.weight"]?.asType(.float32),
        let ln1B = wts["\(pfx).self_attn_layer_norm.bias"]?.asType(.float32),
        let ln2W = wts["\(pfx).final_layer_norm.weight"]?.asType(.float32),
        let ln2B = wts["\(pfx).final_layer_norm.bias"]?.asType(.float32)
    else { return x }

    // Pre-LN self-attention
    let n1 = layerNorm(x, w: ln1W, b: ln1B)
    guard
        let qLin = linear(n1, wts: wts, weightKey: "\(pfx).self_attn.q_proj.weight", biasKey: "\(pfx).self_attn.q_proj.bias"),
        let kLin = linear(n1, wts: wts, weightKey: "\(pfx).self_attn.k_proj.weight", biasKey: "\(pfx).self_attn.k_proj.bias"),
        let vLin = linear(n1, wts: wts, weightKey: "\(pfx).self_attn.v_proj.weight", biasKey: "\(pfx).self_attn.v_proj.bias")
    else { return x }
    let q  = qLin.reshaped([seq, numHeads, headDim]).transposed(axes: [1, 0, 2])
    let k  = kLin.reshaped([seq, numHeads, headDim]).transposed(axes: [1, 0, 2])
    let v  = vLin.reshaped([seq, numHeads, headDim]).transposed(axes: [1, 0, 2])

    let scale   = 1.0 / sqrt(Float(headDim))
    let scores  = matmul(q, k.transposed(axes: [0, 2, 1])) * scale  // [H, seq, seq]
    let attnW   = softmax(scores, axis: -1)
    let attnOut = matmul(attnW, v)                                   // [H, seq, dim]
        .transposed(axes: [1, 0, 2])
        .reshaped([seq, dModel])
    guard let proj = linear(attnOut, wts: wts, weightKey: "\(pfx).self_attn.out_proj.weight", biasKey: "\(pfx).self_attn.out_proj.bias")
    else { return x }
    let h       = x + proj

    // Pre-LN FFN (GELU)
    let n2   = layerNorm(h, w: ln2W, b: ln2B)
    guard
        let ffn1Pre = linear(n2, wts: wts, weightKey: "\(pfx).fc1.weight", biasKey: "\(pfx).fc1.bias")
    else { return h }
    let ffn1 = geluApprox(ffn1Pre)
    guard
        let ffn2 = linear(ffn1, wts: wts, weightKey: "\(pfx).fc2.weight", biasKey: "\(pfx).fc2.bias")
    else { return h }
    return h + ffn2
}

/// Full audio encoder:
/// mel `[T,128]` → conv2d x3 (stride 2) → conv_out → positional embedding
/// → 24 transformer blocks → ln_post → proj1 → GELU → proj2.
private func runAudioEncoder(_ mel: MLXArray, wts: [String: MLXArray]) -> MLXArray? {
    let pfx       = "audio_tower"
    let dModel    = 1024
    let numHeads  = 16
    let numLayers = 24
    let outputDim = 2048

    // mel is [T,128] -> [1,128,T,1] for MLX conv2d ([N,H,W,C]).
    var convIn = mel.transposed(axes: [1, 0]).expandedDimensions(axis: 0).expandedDimensions(axis: 3).asType(.float32)
    guard convIn.shape[1] == 128 else { return nil }

    func convBlock(_ x: MLXArray, weightKey: String, biasKey: String) -> MLXArray? {
        guard
            let w = wts[weightKey]?.asType(.float32),
            let b = wts[biasKey]?.asType(.float32)
        else { return nil }
        let y = conv2d(x, w, stride: 2, padding: 1)
        let yb = y + b.reshaped([1, 1, 1, b.shape[0]])
        return geluApprox(yb)
    }

    guard
        let c1 = convBlock(convIn, weightKey: "\(pfx).conv2d1.weight", biasKey: "\(pfx).conv2d1.bias"),
        let c2 = convBlock(c1,     weightKey: "\(pfx).conv2d2.weight", biasKey: "\(pfx).conv2d2.bias"),
        let c3 = convBlock(c2,     weightKey: "\(pfx).conv2d3.weight", biasKey: "\(pfx).conv2d3.bias"),
        let convOutW = wts["\(pfx).conv_out.weight"]?.asType(.float32)
    else { return nil }

    // [B,F,T,C] -> [B,T,C,F] -> [B,T,C*F], with B=1
    let bsz = c3.shape[0]
    let fdim = c3.shape[1]
    let tdim = c3.shape[2]
    let cdim = c3.shape[3]
    var x = c3.transposed(axes: [0, 2, 3, 1]).reshaped([bsz, tdim, cdim * fdim]) // [1,T,7680]
    x = matmul(x, convOutW.T)                                                      // [1,T,1024]
    x = x[0]                                                                        // [T,1024]

    let seqLen = x.shape[0]
    guard seqLen > 0 else { return nil }
    let posEmb = sinusoidPositionEmbedding(length: seqLen, channels: dModel)
    x = x + posEmb[..<seqLen]

    // ── 24 transformer encoder layers ────────────────────────────────────────
    for i in 0..<numLayers {
        x = audioEncoderBlock(x, wts: wts, pfx: "\(pfx).layers.\(i)",
                              dModel: dModel, numHeads: numHeads)
    }

    // ── Final normalization + projection stack ───────────────────────────────
    if let lnW = wts["\(pfx).ln_post.weight"]?.asType(.float32),
       let lnB = wts["\(pfx).ln_post.bias"]?.asType(.float32) {
        x = layerNorm(x, w: lnW, b: lnB)
    }

    guard
        let p1 = linear(x, wts: wts, weightKey: "\(pfx).proj1.weight", biasKey: "\(pfx).proj1.bias"),
        let p2 = linear(geluApprox(p1), wts: wts, weightKey: "\(pfx).proj2.weight", biasKey: "\(pfx).proj2.bias")
    else { return nil }
    x = p2
    guard x.shape[1] == outputDim else { return nil }

    return x  // [audioFrames, 2048]
}

// MARK: - Qwen3 Text Decoder Layer (GQA + SwiGLU + RMSNorm)

/// One Qwen3 decoder layer.  Returns updated hidden states and updated KV entry.
private func qwen3DecoderBlock(
    _ x: MLXArray,
    wts: [String: MLXArray],
    pfx: String,
    numQH: Int,
    numKVH: Int,
    headDim: Int,
    positions: MLXArray,
    kvEntry: KVEntry?,
    theta: Float
) -> (MLXArray, KVEntry) {
    let seq        = x.shape[0]
    let emptyKV    = KVEntry(k: MLXArray.zeros([0, numKVH, headDim]),
                             v: MLXArray.zeros([0, numKVH, headDim]))

    guard
        let inNW = wts["\(pfx).input_layernorm.weight"]?.asType(.float32),
        let paNW = wts["\(pfx).post_attention_layernorm.weight"]?.asType(.float32)
    else { return (x, emptyKV) }

    // Pre-norm + QKV projections
    let normed = rmsNorm(x, weight: inNW)
    guard
        let qProj = linear(normed, wts: wts, weightKey: "\(pfx).self_attn.q_proj.weight"),
        let kProj = linear(normed, wts: wts, weightKey: "\(pfx).self_attn.k_proj.weight"),
        let vProj = linear(normed, wts: wts, weightKey: "\(pfx).self_attn.v_proj.weight")
    else { return (x, emptyKV) }
    var q = qProj.reshaped([seq, numQH, headDim])   // [seq, QH, dim]
    var k = kProj.reshaped([seq, numKVH, headDim])
    let v = vProj.reshaped([seq, numKVH, headDim])

    // Per-head query/key normalisation (Qwen3 feature)
    if let qnW = wts["\(pfx).self_attn.q_norm.weight"]?.asType(.float32) {
        q = rmsNorm(q.reshaped([seq * numQH, headDim]), weight: qnW)
             .reshaped([seq, numQH, headDim])
    }
    if let knW = wts["\(pfx).self_attn.k_norm.weight"]?.asType(.float32) {
        k = rmsNorm(k.reshaped([seq * numKVH, headDim]), weight: knW)
             .reshaped([seq, numKVH, headDim])
    }

    // RoPE
    let posQ: MLXArray
    if positions.shape[0] == seq {
        posQ = positions
    } else {
        posQ = MLXArray((0..<seq).map(Int32.init))
    }
    q = applyRoPE(q, positions: posQ, theta: theta)
    k = applyRoPE(k, positions: posQ, theta: theta)

    // KV-cache concatenation
    var ks = k, vs = v
    if let kv = kvEntry, kv.k.shape[0] > 0 {
        ks = concatenated([kv.k, k], axis: 0)
        vs = concatenated([kv.v, v], axis: 0)
    }
    let newKV = KVEntry(k: ks, v: vs)

    // GQA: tile KV heads to match Q heads
    let repeat_ = numQH / numKVH
    let ksExp: MLXArray
    let vsExp: MLXArray
    if repeat_ > 1 {
        // Repeat KV heads: [kvLen, numKVH, dim] → [kvLen, numQH, dim]
        ksExp = concatenated((0..<repeat_).map { _ in ks }, axis: 1)  // simple tile
        vsExp = concatenated((0..<repeat_).map { _ in vs }, axis: 1)
    } else {
        ksExp = ks; vsExp = vs
    }

    // Scaled dot-product attention: q [seq, QH, dim]  k [kvLen, QH, dim]
    let scale   = 1.0 / sqrt(Float(headDim))
    let qH      = q.transposed(axes: [1, 0, 2])                      // [QH, seq, dim]
    let kH      = ksExp.transposed(axes: [1, 0, 2])                  // [QH, kvLen, dim]
    let vH      = vsExp.transposed(axes: [1, 0, 2])
    let scores  = matmul(qH, kH.transposed(axes: [0, 2, 1])) * scale // [QH, seq, kvLen]
    let attnW   = softmax(scores, axis: -1)
    let attnOut = matmul(attnW, vH)                                   // [QH, seq, dim]
        .transposed(axes: [1, 0, 2])
        .reshaped([seq, numQH * headDim])                             // [seq, hiddenSize]
    guard
        let attnProj = linear(attnOut, wts: wts, weightKey: "\(pfx).self_attn.o_proj.weight")
    else { return (x, newKV) }
    let h = x + attnProj

    // SwiGLU FFN
    let n2 = rmsNorm(h, weight: paNW)
    guard
        let gate = linear(n2, wts: wts, weightKey: "\(pfx).mlp.gate_proj.weight"),
        let up = linear(n2, wts: wts, weightKey: "\(pfx).mlp.up_proj.weight")
    else { return (h, newKV) }

    guard
        let ffn = linear(siluActivation(gate) * up, wts: wts, weightKey: "\(pfx).mlp.down_proj.weight")
    else { return (h, newKV) }
    return (h + ffn, newKV)
}

// MARK: - Greedy Decoder

private struct Qwen3ASRSpecialTokens {
    static let audioStart: Int  = 151_669   // <|audio_start|>
    static let audioEnd:   Int  = 151_670   // <|audio_end|>
    static let audioPad:   Int  = 151_676   // <|audio_pad|>
    static let asrText:    Int  = 151_704   // <|asr_text|>
    static let eos:        Int  = 151_645   // <|im_end|>
}

private struct Qwen3DecoderConfig {
    let hiddenSize    = 2048
    let numQHeads     = 16
    let numKVHeads    = 8
    let headDim       = 128
    let numLayers     = 28
    let vocabSize     = 151_936
    let ropeTheta     = Float(1_000_000.0)
    let maxNewTokens  = 128
}

/// Full greedy-decode pass: audio context → transcribed text tokens.
private func greedyDecode(
    audioCtx: MLXArray,
    wts: [String: MLXArray],
    vocabulary: [Int: String]
) -> String? {
    let cfg   = Qwen3DecoderConfig()
    let tok   = Qwen3ASRSpecialTokens.self
    let pfxM  = "model"

    guard let normW = wts["\(pfxM).norm.weight"]?.asType(.float32) else { return nil }

    /// Helper: embed a single discrete token.
    func embed(_ id: Int) -> MLXArray? {
        tokenEmbedding(id, wts: wts, tableKey: "\(pfxM).embed_tokens.weight")
    }

    // ── Build audio prefix embeddings ────────────────────────────────────────
    // Sequence: <audio_start> [audio_context_embeddings] <audio_end> <asr_text>
    guard
        let startEmb = embed(tok.audioStart),
        let endEmb = embed(tok.audioEnd),
        let asrEmb = embed(tok.asrText)
    else { return nil }
    let prefixEmb = concatenated(
        [
            startEmb,
            audioCtx,
            endEmb,
            asrEmb,
        ],
        axis: 0
    )
    let prefixLen = prefixEmb.shape[0]

    // ── Prefill: run all decoder layers on prefix to populate KV cache ───────
    var kvCaches  = [KVEntry?](repeating: nil, count: cfg.numLayers)
    var positions = MLXArray((0..<prefixLen).map { Int32($0) })
    var hidden    = prefixEmb

    for i in 0..<cfg.numLayers {
        let (out, kv) = qwen3DecoderBlock(
            hidden, wts: wts, pfx: "\(pfxM).layers.\(i)",
            numQH: cfg.numQHeads, numKVH: cfg.numKVHeads, headDim: cfg.headDim,
            positions: positions, kvEntry: kvCaches[i], theta: cfg.ropeTheta
        )
        hidden    = out
        kvCaches[i] = kv
    }

    // Logits from last prefill position
    let lastH = rmsNorm(hidden[prefixLen - 1].expandedDimensions(axis: 0), weight: normW)
    guard var logits = projectToVocabulary(lastH, wts: wts) else { return nil }   // [1, vocabSize]

    // ── Autoregressive generation ────────────────────────────────────────────
    var outputIds  = [Int]()
    var genPos     = prefixLen
    let audioFrameCount = max(1, audioCtx.shape[0])
    let adaptiveTokenBudget = max(24, min(cfg.maxNewTokens, audioFrameCount * 3))
    let decodeDeadline = Date().addingTimeInterval(
        min(10.0, max(3.0, Double(audioFrameCount) * 0.05))
    )

    for _ in 0..<adaptiveTokenBudget {
        if Date() >= decodeDeadline {
            break
        }

        // Greedy: pick argmax over vocab dimension
        let nextId = Int(logits.argMax(axis: -1).asArray(Int32.self)[0])
        if nextId == tok.eos { break }
        outputIds.append(nextId)

        // Embed next token and decode one step
        guard let nextEmbedding = embed(nextId) else { break }
        hidden        = nextEmbedding
        positions     = MLXArray([Int32(genPos)])
        genPos       += 1

        for i in 0..<cfg.numLayers {
            let (out, kv) = qwen3DecoderBlock(
                hidden, wts: wts, pfx: "\(pfxM).layers.\(i)",
                numQH: cfg.numQHeads, numKVH: cfg.numKVHeads, headDim: cfg.headDim,
                positions: positions, kvEntry: kvCaches[i], theta: cfg.ropeTheta
            )
            hidden       = out
            kvCaches[i]  = kv
        }
        let lh = rmsNorm(hidden[0].expandedDimensions(axis: 0), weight: normW)
        guard let nextLogits = projectToVocabulary(lh, wts: wts) else { break }
        logits = nextLogits
    }

    guard !outputIds.isEmpty else { return nil }

    // ── Decode token IDs → string ────────────────────────────────────────────
    var result = ""
    for id in outputIds {
        if let piece = vocabulary[id] {
            // Qwen tokenizer uses Ġ (U+0120) for leading space, Ċ (U+010A) for newline
            result += piece
                .replacingOccurrences(of: "\u{0120}", with: " ")
                .replacingOccurrences(of: "\u{010A}", with: "\n")
                .replacingOccurrences(of: "\u{2581}", with: " ")
        }
    }
    let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

// MARK: - Qwen3ASREngine

/// Singleton managing on-device speech recognition via Qwen3-ASR-1.7B.
/// Follows the same API contract as AdvancedLLMFormatter for UI bindings.
@Observable
@MainActor
final class Qwen3ASREngine {

    static let shared = Qwen3ASREngine()
    static let modelId    = "aufklarer/Qwen3-ASR-1.7B-MLX-8bit"
    static let modelBytes = 2_460.0 * 1_024 * 1_024   // ~2.46 GB

    // ── Observable download / install state ─────────────────────────────────
    var downloadProgress: Double = 0
    var isInstalling: Bool       = false
    var installError: String?    = nil
    var downloadSpeed: String    = ""
    var downloadedMB: String     = ""
    var isPaused: Bool           = false

    // ── Loaded model state ──────────────────────────────────────────────────
    private var weights:    [String: MLXArray]? = nil
    private var vocabulary: [Int: String]       = [:]

    private var installTask: Task<Void, Never>?       = nil
    private var activeFileTask: URLSessionDownloadTask? = nil
    private var activeFileSession: URLSession?          = nil
    private let log = Logger(subsystem: "com.zphyr.app", category: "Qwen3ASR")

    private enum InstallDownloadError: LocalizedError {
        case badHTTPStatus(file: String, statusCode: Int, url: URL)

        var errorDescription: String? {
            switch self {
            case .badHTTPStatus(let file, let statusCode, let url):
                return "Failed to download \(file) (HTTP \(statusCode)) from \(url.absoluteString)"
            }
        }
    }

    /// Local directory where model files are cached.
    static let cacheDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
            .appendingPathComponent("models--aufklarer--Qwen3-ASR-1.7B-MLX-8bit")
            .appendingPathComponent("snapshots/main")
    }()

    /// Best-effort discovery of an installed snapshot on disk.
    static func resolveInstallURL() -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: cacheDir.path) {
            return cacheDir
        }

        let root = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub/models--aufklarer--Qwen3-ASR-1.7B-MLX-8bit/snapshots")
        guard fm.fileExists(atPath: root.path),
              let candidates = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
            return nil
        }

        if let main = candidates.first(where: { $0.lastPathComponent == "main" }) {
            return main
        }

        return candidates.max(by: {
            let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhs < rhs
        })
    }

    private init() {}

    // MARK: Installation

    func installModel() async {
        guard !isInstalling else { return }
        isInstalling     = true
        installError     = nil
        downloadProgress = 0
        downloadSpeed    = ""
        downloadedMB     = ""

        let task = Task<Void, Never> {
            do {
                try await self.downloadModelFiles()
                guard !Task.isCancelled else { return }
                try await self.loadWeightsAndTokenizer()
                AppState.shared.qwen3asrInstalled = true
                self.downloadProgress = 1.0
                self.downloadSpeed    = ""
                self.downloadedMB     = ""
                self.log.notice("[Qwen3ASR] installation complete")
            } catch is CancellationError {
                self.log.notice("[Qwen3ASR] install cancelled")
            } catch {
                if !Task.isCancelled {
                    self.installError = error.localizedDescription
                    self.log.error("[Qwen3ASR] install error: \(error.localizedDescription)")
                }
            }
            self.isInstalling = false
            self.installTask  = nil
        }
        installTask = task
        await task.value
    }

    func cancelInstall() {
        activeFileTask?.cancel()
        activeFileTask    = nil
        activeFileSession?.invalidateAndCancel()
        activeFileSession = nil
        installTask?.cancel()
        installTask       = nil
        isInstalling      = false
        isPaused          = false
        downloadProgress  = 0
        downloadSpeed     = ""
        downloadedMB      = ""
        log.notice("[Qwen3ASR] install cancelled by user")
    }

    func pauseInstall() {
        activeFileTask?.suspend()
        isPaused      = true
        downloadSpeed = ""
    }

    func resumeInstall() {
        activeFileTask?.resume()
        isPaused = false
    }

    /// Silently load an already-downloaded model from the local cache.
    func loadIfInstalled() async {
        guard AppState.shared.qwen3asrInstalled, weights == nil else { return }
        do {
            try await loadWeightsAndTokenizer()
            log.notice("[Qwen3ASR] loaded from disk cache")
        } catch {
            AppState.shared.qwen3asrInstalled = false
            log.warning("[Qwen3ASR] cache missing or corrupt — resetting flag")
        }
    }

    func unload() {
        weights    = nil
        vocabulary = [:]
        log.notice("[Qwen3ASR] model unloaded from memory")
    }

    var isLoaded: Bool { weights != nil && !vocabulary.isEmpty }

    // MARK: Transcription

    /// Transcribe Float32 16 kHz mono PCM samples.
    /// Returns nil on failure and lets caller decide the UI error handling.
    func transcribe(_ samples: [Float], language: String?) async -> String? {
        guard let wts = weights, !vocabulary.isEmpty else {
            log.warning("[Qwen3ASR] transcribe called but model not loaded")
            return nil
        }
        guard !samples.isEmpty else { return nil }

        let voc = vocabulary   // capture for task
        return await Task(priority: .userInitiated) { [log = log] in
            // Step 1 — mel spectrogram
            let mel = MelSpec.compute(samples: samples)   // [T, 128]

            // Step 2 — audio encoder
            guard let audioCtx = runAudioEncoder(mel, wts: wts) else {
                log.error("[Qwen3ASR] audio encoder returned nil")
                return nil
            }

            // Step 3 — greedy text decoder
            return greedyDecode(audioCtx: audioCtx, wts: wts, vocabulary: voc)
        }.value
    }

    // MARK: - Private: Download

    private func downloadModelFiles() async throws {
        let fm  = FileManager.default
        let dir = Self.cacheDir
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let files: [(name: String, approxBytes: Double, required: Bool)] = [
            ("config.json",           50_000, true),
            ("vocab.json",         3_000_000, true),
            ("merges.txt",         1_500_000, true),
            ("tokenizer_config.json", 20_000, false),
            ("model.safetensors", Self.modelBytes, true)
        ]

        let totalBytes = files.reduce(0.0) { $0 + $1.approxBytes }
        var doneBytes: Double = 0
        let startedAt = Date()

        for file in files {
            guard !Task.isCancelled else { throw CancellationError() }

            let dest = dir.appendingPathComponent(file.name)
            if fm.fileExists(atPath: dest.path) {
                doneBytes += file.approxBytes
                downloadProgress = min(doneBytes / totalBytes, 0.99)
                log.notice("[Qwen3ASR] \(file.name) already cached")
                continue
            }

            let base   = "https://huggingface.co/\(Self.modelId)/resolve/main/"
            let remote = URL(string: base + file.name)!
            log.notice("[Qwen3ASR] downloading \(file.name) …")

            let (tmp, resp) = try await downloadFileWithDelegate(
                from: remote,
                bytesBefore: doneBytes,
                totalBytes: totalBytes,
                startedAt: startedAt
            )

            guard let http = resp as? HTTPURLResponse else {
                try? fm.removeItem(at: tmp)
                throw URLError(.badServerResponse)
            }
            guard http.statusCode == 200 else {
                try? fm.removeItem(at: tmp)
                if !file.required {
                    log.warning("[Qwen3ASR] optional \(file.name) unavailable (HTTP \(http.statusCode)); skipping")
                    doneBytes += file.approxBytes
                    downloadProgress = min(doneBytes / totalBytes, 0.99)
                    continue
                }
                throw InstallDownloadError.badHTTPStatus(file: file.name, statusCode: http.statusCode, url: remote)
            }
            if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
            try fm.moveItem(at: tmp, to: dest)

            doneBytes += file.approxBytes
            downloadProgress = min(doneBytes / totalBytes, 0.99)
        }
    }

    /// Downloads a single file using URLSessionDownloadTask so we can suspend/resume.
    private func downloadFileWithDelegate(
        from url: URL,
        bytesBefore: Double,
        totalBytes: Double,
        startedAt: Date
    ) async throws -> (URL, URLResponse?) {
        let delegate = DownloadFileDelegate()
        let config   = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 300
        config.timeoutIntervalForResource = 86_400
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        let task    = session.downloadTask(with: url)
        activeFileTask    = task
        activeFileSession = session

        delegate.onProgress = { [weak self] written, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let fileBytes   = Double(written)
                let overallFrac = min((bytesBefore + fileBytes) / totalBytes, 0.99)
                self.downloadProgress = overallFrac
                guard !self.isPaused else { return }
                let elapsed = Date().timeIntervalSince(startedAt)
                guard elapsed > 1 else { return }
                let bps = (bytesBefore + fileBytes) / elapsed
                self.downloadSpeed = bps >= 1_048_576
                    ? String(format: "%.1f MB/s", bps / 1_048_576)
                    : String(format: "%.0f KB/s", bps / 1_024)
                self.downloadedMB = String(format: "%.0f / %.0f MB",
                    (bytesBefore + fileBytes) / 1_048_576,
                    totalBytes / 1_048_576)
            }
        }

        defer {
            activeFileTask    = nil
            activeFileSession = nil
            session.invalidateAndCancel()
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                delegate.cont = cont
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: - Private: Weight & Tokenizer Load

    private func loadWeightsAndTokenizer() async throws {
        let dir        = Self.cacheDir
        let weightsURL = dir.appendingPathComponent("model.safetensors")
        guard FileManager.default.fileExists(atPath: weightsURL.path) else {
            throw NSError(
                domain: "Qwen3ASR", code: -1,
                userInfo: [NSLocalizedDescriptionKey:
                    "model.safetensors not found at \(weightsURL.path)"])
        }

        // Load safetensors weights (requires MLX module)
        log.notice("[Qwen3ASR] loading weights from \(weightsURL.path) …")
        let loaded = try loadArrays(url: weightsURL)   // [String: MLXArray]
        log.notice("[Qwen3ASR] \(loaded.count) weight tensors loaded")

        // Load vocabulary for token-id → text decoding
        let vocabURL  = dir.appendingPathComponent("vocab.json")
        var rev       = [Int: String]()
        if let data = try? Data(contentsOf: vocabURL),
           let dict = try? JSONDecoder().decode([String: Int].self, from: data) {
            for (piece, id) in dict { rev[id] = piece }
            log.notice("[Qwen3ASR] vocabulary loaded: \(rev.count) entries")
        } else {
            log.warning("[Qwen3ASR] vocab.json missing or unreadable")
        }

        await MainActor.run {
            self.weights    = loaded
            self.vocabulary = rev
        }
    }

    // MARK: - Helpers

    private static func formatSpeed(_ bps: Double) -> String {
        bps >= 1_048_576
            ? String(format: "%.1f MB/s", bps / 1_048_576)
            : String(format: "%.0f KB/s", bps / 1_024)
    }
}

// MARK: - URLSession download delegate helper

private final class DownloadFileDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    typealias Cont = CheckedContinuation<(URL, URLResponse?), Error>
    var cont: Cont?
    var onProgress: ((Int64, Int64) -> Void)?

    func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Move to a stable temp path before the session cleans it up.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.moveItem(at: location, to: tmp)
        cont?.resume(returning: (tmp, t.response))
        cont = nil
    }

    func urlSession(_ s: URLSession, task t: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, cont != nil else { return }
        let ns = error as NSError
        // NSURLErrorCancelled = task was cancelled/suspended-then-cancelled; treat as CancellationError
        cont?.resume(throwing: ns.code == NSURLErrorCancelled ? CancellationError() : error)
        cont = nil
    }

    func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask,
                    didWriteData _: Int64, totalBytesWritten w: Int64,
                    totalBytesExpectedToWrite total: Int64) {
        onProgress?(w, total)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Compile-time stub (MLX not linked to the target)
// ═══════════════════════════════════════════════════════════════════════════════
#else

@Observable
@MainActor
final class Qwen3ASREngine {
    static let shared     = Qwen3ASREngine()
    static let modelId    = "aufklarer/Qwen3-ASR-1.7B-MLX-8bit"
    static let modelBytes = 2_460.0 * 1_024 * 1_024

    var downloadProgress: Double = 0
    var isInstalling: Bool       = false
    var installError: String?    =
        "⚠️ Link MLX + MLXNN to the Zphyr target to enable Qwen3-ASR."
    var downloadSpeed: String    = ""
    var downloadedMB: String     = ""
    var isPaused: Bool           = false
    var isLoaded: Bool           = false

    static let cacheDir: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/huggingface/hub/models--aufklarer--Qwen3-ASR-1.7B-MLX-8bit/snapshots/main")

    static func resolveInstallURL() -> URL? {
        let fm = FileManager.default
        return fm.fileExists(atPath: cacheDir.path) ? cacheDir : nil
    }

    private init() {}
    func installModel()    async {}
    func cancelInstall()         {}
    func pauseInstall()          {}
    func resumeInstall()         {}
    func loadIfInstalled() async {}
    func unload()                {}
    func transcribe(_ samples: [Float], language: String?) async -> String? { nil }
}

#endif
