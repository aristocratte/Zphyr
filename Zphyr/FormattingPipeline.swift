//
//  FormattingPipeline.swift
//  Zphyr
//
//  Layered post-ASR pipeline. 7 deterministic stages + 1 optional model stage.
//  Single source of truth for post-transcription formatting logic.
//  Replaces the inline postProcess()/applyFormattingPipeline()/capitalizeProperNouns()
//  flow that was previously spread across DictationEngine and TranscriptStabilizer.
//

import Foundation
import os

// MARK: - Pipeline Orchestrator

@MainActor
final class FormattingPipeline {

    static let shared = FormattingPipeline()

    private static let log = Logger(subsystem: "com.zphyr.app", category: "Pipeline")

    /// The most recent run's trace, for metrics/diagnostics.
    private(set) var lastTrace: [StageTrace] = []

    private let transcriptCleanup = TranscriptCleanupStage()
    private let disfluencyRemoval = DisfluencyRemovalStage()
    private let punctuationCapitalization = PunctuationCapitalizationStage()
    private let formattingNormalization = FormattingNormalizationStage()
    private let contextualRewrite = ContextualRewriteStage()
    private let commandExtraction = CommandExtractionStage()
    private let finalSafety = FinalSafetyStage()

    private var stages: [any PipelineStage] {
        [transcriptCleanup, disfluencyRemoval, punctuationCapitalization,
         formattingNormalization, contextualRewrite, commandExtraction, finalSafety]
    }

    /// Runs the full pipeline. Returns the final result with trace and command info.
    func run(_ input: TranscriptionInput) async -> PipelineResult {
        let pipelineStart = CFAbsoluteTimeGetCurrent()

        let state = AppState.shared
        state.refreshPerformanceProfile()

        let effectiveMode = PerformanceRouter.shared.effectiveFormattingMode(
            preferred: state.formattingMode,
            profile: state.performanceProfile
        )

        let metadata = PipelineMetadata(
            languageCode: input.languageCode,
            targetBundleID: input.targetBundleID,
            tone: activeTone(bundleID: input.targetBundleID),
            defaultCodeStyle: state.defaultCodeStyle,
            formattingMode: effectiveMode,
            isProModeUnlocked: state.isProModeUnlocked,
            isLLMLoaded: AdvancedLLMFormatter.shared.isModelLoaded
        )

        // ── Abort command pre-scan ─────────────────────────────────────────
        let (abortCommand, cleanedText) = CommandInterpreter.shared.scanForAbort(
            input.rawText, languageCode: input.languageCode
        )
        if abortCommand != .none {
            let abortTrace = StageTrace.record(
                name: "AbortCommandScan", index: 0,
                input: input.rawText, output: "",
                durationMs: (CFAbsoluteTimeGetCurrent() - pipelineStart) * 1_000,
                transformations: ["detected_abort_command:\(abortCommand)"]
            )
            lastTrace = [abortTrace]
            Self.log.notice("[Pipeline] abort command detected — short-circuiting")
            return PipelineResult(
                finalText: "",
                extractedCommand: abortCommand,
                trace: [abortTrace],
                totalDurationMs: (CFAbsoluteTimeGetCurrent() - pipelineStart) * 1_000,
                listBlocksCount: 0
            )
        }

        // ── Run stages ─────────────────────────────────────────────────────
        var io = StageIO(
            text: cleanedText,
            extractedCommand: .none,
            metadata: metadata
        )

        var traces: [StageTrace] = []
        traces.reserveCapacity(stages.count)

        for (index, stage) in stages.enumerated() {
            let stageStart = CFAbsoluteTimeGetCurrent()
            let inputText = io.text
            io = await stage.process(io)
            let durationMs = (CFAbsoluteTimeGetCurrent() - stageStart) * 1_000

            let trace = StageTrace.record(
                name: stage.name,
                index: index,
                input: inputText,
                output: io.text,
                durationMs: durationMs,
                transformations: [],
                isModelBased: stage.isModelBased,
                wasSkipped: inputText == io.text && !stage.isModelBased
            )
            traces.append(trace)

            Self.log.notice(
                "[Pipeline] stage=\(stage.name, privacy: .public) dur=\(String(format: "%.1f", durationMs), privacy: .public)ms inLen=\(inputText.count, privacy: .public) outLen=\(io.text.count, privacy: .public)"
            )
        }

        let totalMs = (CFAbsoluteTimeGetCurrent() - pipelineStart) * 1_000
        lastTrace = traces

        Self.log.notice(
            "[Pipeline] completed stages=\(traces.count, privacy: .public) total=\(String(format: "%.1f", totalMs), privacy: .public)ms command=\(String(describing: io.extractedCommand), privacy: .public)"
        )

        return PipelineResult(
            finalText: io.text,
            extractedCommand: io.extractedCommand,
            trace: traces,
            totalDurationMs: totalMs,
            listBlocksCount: formattingNormalization.lastListBlocksCount
        )
    }
}

// MARK: - Stage 1: Transcript Cleanup

/// Non-destructive cleanup: Unicode NFC, whitespace normalization, line break normalization.
/// Does NOT lowercase, does NOT strip punctuation, does NOT modify casing.
@MainActor
struct TranscriptCleanupStage: PipelineStage {
    let name = "TranscriptCleanup"

    func process(_ input: StageIO) -> StageIO {
        guard !input.text.isEmpty else { return input }

        var text = input.text

        // Unicode NFC normalization for consistent downstream matching
        text = text.precomposedStringWithCanonicalMapping

        // Normalize line breaks
        text = text
            .replacingOccurrences(of: "\\r\\n?", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)

        // Collapse horizontal whitespace (tabs, multiple spaces) to single space
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)

        // Trim leading/trailing whitespace per line
        text = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        return input.withText(text)
    }
}

// MARK: - Stage 2: Disfluency Removal

/// Conservative filler word removal and exact word-level repetition removal.
/// Only removes unambiguous fillers. Does NOT remove false starts or partial words.
@MainActor
final class DisfluencyRemovalStage: PipelineStage {
    let name = "DisfluencyRemoval"

    private var fillerRegexCache: [String: [NSRegularExpression]] = [:]

    private let repetitionRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(\w{2,})(?:\s+\1){1,3}\b"#
    )

    func process(_ input: StageIO) -> StageIO {
        guard !input.text.isEmpty else { return input }
        var text = input.text
        let lang = input.metadata.languageCode

        // Remove filler words
        for regex in fillerRemovalRegexes(for: lang) {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }

        // Conservative repetition removal: only exact consecutive word repeats
        // "I I think" → "I think" but NOT "no no no" (short emphasis words ≤ 3 chars preserved)
        if let regex = repetitionRegex {
            // Custom replacement: only collapse if repeated word is > 3 characters
            let nsText = text as NSString
            let range = NSRange(location: 0, length: nsText.length)
            let matches = regex.matches(in: text, range: range)

            // Process matches in reverse to preserve indices
            var mutableText = text
            for match in matches.reversed() {
                guard match.numberOfRanges >= 2,
                      let wordRange = Range(match.range(at: 1), in: mutableText),
                      let fullRange = Range(match.range, in: mutableText) else { continue }
                let word = String(mutableText[wordRange])
                // Keep short-word repetitions (emphasis patterns like "no no")
                guard word.count > 3 else { continue }
                mutableText.replaceSubrange(fullRange, with: word)
            }
            text = mutableText
        }

        // Collapse spaces left by removals
        text = text
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return input.withText(text)
    }

    // MARK: - Filler Data

    private func fillerRemovalRegexes(for languageCode: String) -> [NSRegularExpression] {
        if let cached = fillerRegexCache[languageCode] {
            return cached
        }
        let compiled = fillerWords(for: languageCode).compactMap { filler -> NSRegularExpression? in
            let escaped = NSRegularExpression.escapedPattern(for: filler)
            return try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: [.caseInsensitive])
        }
        fillerRegexCache[languageCode] = compiled
        return compiled
    }

    private func fillerWords(for languageCode: String) -> [String] {
        let common = ["hmm", "hm", "mhm"]
        let fr = [
            "euh", "euh,", "euh.", "bah", "bah,", "ben", "ben,",
            "voilà,", "voilà.", "voilà", "donc,", "alors,", "enfin,",
            "genre,", "genre", "hein,", "hein", "quoi,",
        ]
        let en = ["uh", "um", "uh,", "um,", "like,", "you know,", "you know", "right,", "so,"]
        let es = ["eh", "eh,", "eh.", "emm", "este", "pues", "o sea", "bueno,"]
        let zh = ["嗯", "呃", "那个", "就是", "然后"]
        let ja = ["えー", "えっと", "あの", "その", "まあ"]
        let ru = ["ээ", "эм", "ну", "как бы", "это"]

        switch SupportedUILanguage.fromWhisperCode(languageCode) {
        case .fr: return fr + common
        case .en: return en + common
        case .es: return es + common
        case .zh: return zh + common
        case .ja: return ja + common
        case .ru: return ru + common
        }
    }
}

// MARK: - Stage 3: Punctuation & Capitalization

/// Spoken punctuation → symbols, sentence capitalization, proper noun capitalization,
/// transition sentence boundaries.
@MainActor
final class PunctuationCapitalizationStage: PipelineStage {
    let name = "PunctuationCapitalization"

    private var formalPunctuationRuleCache: [String: [(regex: NSRegularExpression, replacement: String)]] = [:]
    private var transitionRuleCache: [String: [TransitionBoundaryRule]] = [:]

    private let spaceBeforePunctuationRegex = try? NSRegularExpression(pattern: "\\s+([,;:.!?\\)])")
    private let missingSpaceAfterPunctuationRegex = try? NSRegularExpression(pattern: "([,;:.!?])([^\\s])")
    private let spaceAfterOpenParenRegex = try? NSRegularExpression(pattern: "\\(\\s+")
    private let dashSpacingRegex = try? NSRegularExpression(pattern: "\\s*—\\s*")

    struct TransitionBoundaryRule {
        let regex: NSRegularExpression
        let replacement: String
    }

    private let properNounRules: [(regex: NSRegularExpression, replacement: String)] = {
        let entries: [(String, String)] = [
            ("\\bpython\\b", "Python"),
            ("\\bswift\\b", "Swift"),
            ("\\bjavascript\\b", "JavaScript"),
            ("\\btypescript\\b", "TypeScript"),
            ("\\bkotlin\\b", "Kotlin"),
            ("\\brust\\b", "Rust"),
            ("\\bgolang\\b", "Go"),
        ]
        return entries.compactMap { pattern, replacement in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return nil
            }
            return (regex, replacement)
        }
    }()

    func process(_ input: StageIO) -> StageIO {
        guard !input.text.isEmpty else { return input }
        var text = input.text
        let lang = input.metadata.languageCode

        // Spoken punctuation → actual symbols
        text = applySpokenPunctuation(to: text, languageCode: lang)

        // Proper noun capitalization (Python, Swift, etc.)
        text = capitalizeProperNouns(in: text)

        return input.withText(text)
    }

    // MARK: - Spoken Punctuation

    private func applySpokenPunctuation(to text: String, languageCode: String) -> String {
        var result = text

        for item in formalPunctuationRules(for: languageCode) {
            let range = NSRange(result.startIndex..., in: result)
            result = item.regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: item.replacement
            )
        }

        // Remove spaces before punctuation
        if let spaceBeforePunctuationRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = spaceBeforePunctuationRegex.stringByReplacingMatches(
                in: result, range: range, withTemplate: "$1"
            )
        }
        // Ensure one space after punctuation when followed by text
        if let missingSpaceAfterPunctuationRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = missingSpaceAfterPunctuationRegex.stringByReplacingMatches(
                in: result, range: range, withTemplate: "$1 $2"
            )
        }
        // Normalize opening parenthesis
        if let spaceAfterOpenParenRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = spaceAfterOpenParenRegex.stringByReplacingMatches(
                in: result, range: range, withTemplate: "("
            )
        }
        // Normalize em dash spacing
        if let dashSpacingRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = dashSpacingRegex.stringByReplacingMatches(
                in: result, range: range, withTemplate: " — "
            )
        }

        result = result
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }

    // MARK: - Proper Nouns

    private func capitalizeProperNouns(in text: String) -> String {
        var result = text
        for rule in properNounRules {
            let range = NSRange(result.startIndex..., in: result)
            result = rule.regex.stringByReplacingMatches(
                in: result, range: range, withTemplate: rule.replacement
            )
        }
        return result
    }

    // MARK: - Punctuation Rule Data

    private func formalPunctuationRules(for languageCode: String) -> [(regex: NSRegularExpression, replacement: String)] {
        if let cached = formalPunctuationRuleCache[languageCode] {
            return cached
        }

        let replacements = formalPunctuationReplacements(for: languageCode) + [
            // French keywords
            ("\\bpoint\\s+virgule\\b", ";"),
            ("\\bdeux\\s+points\\b", ":"),
            ("\\bpoint\\s+d['']interrogation\\b", "?"),
            ("\\bpoint\\s+d['']exclamation\\b", "!"),
            ("\\bpoint\\b", "."),
            ("\\bvirgule\\b", ","),
            ("\\btiret\\b", "—"),
            ("\\bouvrir\\s+parenth[èe]se\\b", "("),
            ("\\bfermer\\s+parenth[èe]se\\b", ")"),

            // English keywords
            ("\\bsemicolon\\b", ";"),
            ("\\bcolon\\b", ":"),
            ("\\bquestion\\s+mark\\b", "?"),
            ("\\bexclamation\\s+mark\\b", "!"),
            ("\\bperiod\\b", "."),
            ("\\bfull\\s+stop\\b", "."),
            ("\\bcomma\\b", ","),
            ("\\bdash\\b", "—"),
            ("\\bopen\\s+parenthesis\\b", "("),
            ("\\bclose\\s+parenthesis\\b", ")")
        ]

        let compiled = replacements.compactMap { pattern, replacement -> (regex: NSRegularExpression, replacement: String)? in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return nil
            }
            return (regex, replacement)
        }
        formalPunctuationRuleCache[languageCode] = compiled
        return compiled
    }

    private func formalPunctuationReplacements(for languageCode: String) -> [(pattern: String, replacement: String)] {
        switch SupportedUILanguage.fromWhisperCode(languageCode) {
        case .es:
            return [
                ("\\bpunto\\s+y\\s+coma\\b", ";"),
                ("\\bdos\\s+puntos\\b", ":"),
                ("\\bsigno\\s+de\\s+interrogación\\b", "?"),
                ("\\bsigno\\s+de\\s+exclamación\\b", "!"),
                ("\\bpunto\\b", "."),
                ("\\bcoma\\b", ","),
                ("\\bguion\\b", "—")
            ]
        case .zh:
            return [
                ("分号", ";"),
                ("冒号", ":"),
                ("问号", "?"),
                ("感叹号", "!"),
                ("句号", "."),
                ("逗号", ",")
            ]
        case .ja:
            return [
                ("句点", "."),
                ("読点", ","),
                ("コロン", ":"),
                ("セミコロン", ";"),
                ("疑問符", "?"),
                ("感嘆符", "!")
            ]
        case .ru:
            return [
                ("\\bточка\\s+с\\s+запятой\\b", ";"),
                ("\\bдвоеточие\\b", ":"),
                ("\\bвопросительный\\s+знак\\b", "?"),
                ("\\bвосклицательный\\s+знак\\b", "!"),
                ("\\bточка\\b", "."),
                ("\\bзапятая\\b", ","),
                ("\\bтире\\b", "—")
            ]
        case .fr, .en:
            return []
        }
    }

    // MARK: - Transition Boundary Data

    func transitionBoundaryRules(for languageCode: String) -> [TransitionBoundaryRule] {
        if let cached = transitionRuleCache[languageCode] {
            return cached
        }

        let rules = transitionStarters(for: languageCode).compactMap { starter -> TransitionBoundaryRule? in
            let escaped = NSRegularExpression.escapedPattern(for: starter)
            let pattern = "(?i)([A-Za-zÀ-ÿ0-9_]{2,})([,]?\\s+)(\(escaped))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return nil
            }
            let replacement = "$1. \(starter.prefix(1).uppercased())\(starter.dropFirst())"
            return TransitionBoundaryRule(regex: regex, replacement: replacement)
        }

        transitionRuleCache[languageCode] = rules
        return rules
    }

    private func transitionStarters(for languageCode: String) -> [String] {
        switch languageCode {
        case "fr":
            return ["ensuite", "puis", "cependant", "néanmoins", "toutefois",
                    "par conséquent", "donc", "ainsi", "de plus", "par ailleurs",
                    "en revanche", "en fait", "d'ailleurs"]
        case "es":
            return ["luego", "después", "sin embargo", "no obstante",
                    "por lo tanto", "así que", "además"]
        case "de":
            return ["dann", "jedoch", "außerdem", "deshalb", "danach"]
        default:
            return ["then", "however", "therefore", "moreover", "furthermore",
                    "subsequently", "additionally", "besides", "nonetheless"]
        }
    }
}

// MARK: - Stage 4: Formatting Normalization

/// Dictionary mappings, contextual snippets, list detection, tone formatting,
/// code formatting, paragraph auto-formatting.
@MainActor
final class FormattingNormalizationStage: PipelineStage {
    let name = "FormattingNormalization"

    private let smartFormatter = SmartTextFormatter()
    private let codeFormatter = CodeFormatter()

    /// Exposed for PipelineResult.listBlocksCount
    private(set) var lastListBlocksCount: Int = 0

    func process(_ input: StageIO) -> StageIO {
        guard !input.text.isEmpty else { return input }
        var text = input.text
        let lang = input.metadata.languageCode

        // ── Smart structural analysis (repetition cleanup + list detection) ──
        let smart = smartFormatter.run(text, languageCode: lang)
        text = smart.cleanedText
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // ── List block rendering (inline markdown) ──
        text = TranscriptStabilizer.renderDetectedListBlocksInline(text, blocks: smart.detectedListBlocks)
        lastListBlocksCount = smart.detectedListBlocks.count

        // ── Dictionary pronunciation mappings ──
        text = applyDictionaryPronunciationMappings(to: text)

        // ── Contextual link/snippet injection ──
        text = applyContextualLinkSnippets(to: text, bundleID: input.metadata.targetBundleID, languageCode: lang)

        // ── Tone formatting (formal/casual/very casual) ──
        text = applyToneFormattingPreservingLists(text, tone: input.metadata.tone, languageCode: lang)

        // ── Code formatting (if trigger/advanced mode) ──
        text = applyCodeFormatting(text, metadata: input.metadata)

        // ── Whitespace normalization ──
        text = normalizeWhitespacePreservingParagraphs(in: text)

        return input.withText(text)
    }

    // MARK: - Dictionary Mappings

    private func applyDictionaryPronunciationMappings(to text: String) -> String {
        var result = text
        for rule in DictionaryStore.shared.pronunciationReplacementRules {
            let range = NSRange(result.startIndex..., in: result)
            result = rule.regex.stringByReplacingMatches(
                in: result, range: range, withTemplate: rule.replacementTemplate
            )
        }
        return result
    }

    // MARK: - Contextual Snippets

    private func applyContextualLinkSnippets(to text: String, bundleID: String?, languageCode: String) -> String {
        var result = text
        let context = snippetContext(for: bundleID)
        let links = snippetLinks()
        let flags = snippetFeatureFlags()
        let triggers = snippetTriggerPhrases(languageCode: languageCode)

        let linkedInReplacement: String
        let socialReplacement: String
        let mailReplacement: String

        switch context {
        case .email:
            if flags.verboseInEmail {
                linkedInReplacement = L10n.ui(
                    for: languageCode,
                    fr: "Retrouvez-nous sur LinkedIn : \(links.linkedinURL)",
                    en: "Find us on LinkedIn: \(links.linkedinURL)",
                    es: "Encuéntranos en LinkedIn: \(links.linkedinURL)",
                    zh: "在 LinkedIn 上找到我们：\(links.linkedinURL)",
                    ja: "LinkedInはこちら: \(links.linkedinURL)",
                    ru: "Найдите нас в LinkedIn: \(links.linkedinURL)"
                )
                socialReplacement = L10n.ui(
                    for: languageCode,
                    fr: "Retrouvez-nous sur nos réseaux sociaux : \(links.socialURL)",
                    en: "Find us on social media: \(links.socialURL)",
                    es: "Encuéntranos en redes sociales: \(links.socialURL)",
                    zh: "在社交媒体找到我们：\(links.socialURL)",
                    ja: "SNSはこちら: \(links.socialURL)",
                    ru: "Найдите нас в соцсетях: \(links.socialURL)"
                )
                mailReplacement = L10n.ui(
                    for: languageCode,
                    fr: "Contactez-nous : \(links.mailtoLink)",
                    en: "Contact us: \(links.mailtoLink)",
                    es: "Contáctanos: \(links.mailtoLink)",
                    zh: "联系我们：\(links.mailtoLink)",
                    ja: "お問い合わせ: \(links.mailtoLink)",
                    ru: "Свяжитесь с нами: \(links.mailtoLink)"
                )
            } else {
                linkedInReplacement = links.linkedinURL
                socialReplacement = links.socialURL
                mailReplacement = links.mailtoLink
            }
        case .social, .general:
            linkedInReplacement = links.linkedinURL
            socialReplacement = links.socialURL
            mailReplacement = links.mailtoLink
        }

        var rules: [ContextualSnippetRule] = []
        if flags.linkedInEnabled {
            rules.append(contentsOf: triggers.linkedIn.map {
                ContextualSnippetRule(pattern: snippetPattern(for: $0), replacement: linkedInReplacement)
            })
        }
        if flags.socialEnabled {
            rules.append(contentsOf: triggers.social.map {
                ContextualSnippetRule(pattern: snippetPattern(for: $0), replacement: socialReplacement)
            })
        }
        if flags.gmailEnabled {
            rules.append(contentsOf: triggers.gmail.map {
                ContextualSnippetRule(pattern: snippetPattern(for: $0), replacement: mailReplacement)
            })
        }

        for rule in rules {
            let replacement = "$1\(escapedRegexReplacement(rule.replacement))"
            result = result.replacingOccurrences(
                of: rule.pattern, with: replacement, options: .regularExpression
            )
        }

        return result
    }

    private enum SnippetContext { case email, social, general }

    private struct ContextualSnippetRule {
        let pattern: String
        let replacement: String
    }

    private func snippetContext(for bundleID: String?) -> SnippetContext {
        guard let bundleID else { return .general }
        let lower = bundleID.lowercased()
        if lower.contains("mail") || lower.contains("outlook") ||
            lower.contains("mimestream") || lower.contains("spark") || lower.contains("airmail") {
            return .email
        }
        if lower.contains("linkedin") || lower.contains("twitter") ||
            lower.contains("facebook") || lower.contains("instagram") || lower.contains("threads") {
            return .social
        }
        return .general
    }

    private func snippetLinks() -> (linkedinURL: String, socialURL: String, mailtoLink: String) {
        let defaults = UserDefaults.standard
        let linkedin = cleanedSnippetValue(defaults.string(forKey: AppState.snippetLinkedInURLKey))
            ?? AppState.snippetLinkedInDefaultURL
        let social = cleanedSnippetValue(defaults.string(forKey: AppState.snippetSocialURLKey))
            ?? AppState.snippetSocialDefaultURL
        let email = cleanedSnippetValue(defaults.string(forKey: AppState.snippetContactEmailKey))
            ?? AppState.snippetContactDefaultEmail
        let mailto = email.lowercased().hasPrefix("mailto:") ? email : "mailto:\(email)"
        return (linkedinURL: linkedin, socialURL: social, mailtoLink: mailto)
    }

    private func snippetTriggerPhrases(languageCode: String) -> (linkedIn: [String], social: [String], gmail: [String]) {
        let defaults = UserDefaults.standard
        let linkedIn = parsedTriggerPhrases(
            defaults.string(forKey: AppState.snippetLinkedInTriggersKey),
            fallbackText: L10n.defaultSnippetTriggers(for: .linkedIn, languageCode: languageCode)
        )
        let social = parsedTriggerPhrases(
            defaults.string(forKey: AppState.snippetSocialTriggersKey),
            fallbackText: L10n.defaultSnippetTriggers(for: .social, languageCode: languageCode)
        )
        let gmail = parsedTriggerPhrases(
            defaults.string(forKey: AppState.snippetGmailTriggersKey),
            fallbackText: L10n.defaultSnippetTriggers(for: .gmail, languageCode: languageCode)
        )
        return (linkedIn, social, gmail)
    }

    private func parsedTriggerPhrases(_ rawText: String?, fallbackText: String) -> [String] {
        let source = cleanedSnippetValue(rawText).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackText
        let parts = source.components(separatedBy: CharacterSet(charactersIn: "\n,;"))
        var seen = Set<String>()
        var result: [String] = []
        for part in parts {
            let normalized = part
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            guard !normalized.isEmpty else { continue }
            let key = normalized.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(normalized)
        }
        return result
    }

    private func snippetPattern(for phrase: String) -> String {
        var escaped = NSRegularExpression.escapedPattern(for: phrase)
        escaped = escaped.replacingOccurrences(of: "\\ ", with: "\\s+")
        escaped = escaped.replacingOccurrences(of: "\\-", with: "[-\\s]?")
        return "(?i)(^|[^\\p{L}\\p{N}_])\(escaped)(?=$|[^\\p{L}\\p{N}_])"
    }

    private func escapedRegexReplacement(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\", with: "\\\\")
           .replacingOccurrences(of: "$", with: "\\$")
    }

    private func snippetFeatureFlags() -> (linkedInEnabled: Bool, socialEnabled: Bool, gmailEnabled: Bool, verboseInEmail: Bool) {
        let defaults = UserDefaults.standard
        let linkedInEnabled = defaults.object(forKey: AppState.snippetLinkedInEnabledKey) == nil
            ? true : defaults.bool(forKey: AppState.snippetLinkedInEnabledKey)
        let socialEnabled = defaults.object(forKey: AppState.snippetSocialEnabledKey) == nil
            ? true : defaults.bool(forKey: AppState.snippetSocialEnabledKey)
        let gmailEnabled = defaults.object(forKey: AppState.snippetGmailEnabledKey) == nil
            ? true : defaults.bool(forKey: AppState.snippetGmailEnabledKey)
        let verboseInEmail = defaults.object(forKey: AppState.snippetVerboseInEmailKey) == nil
            ? true : defaults.bool(forKey: AppState.snippetVerboseInEmailKey)
        return (linkedInEnabled, socialEnabled, gmailEnabled, verboseInEmail)
    }

    private func cleanedSnippetValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    // MARK: - Tone Formatting

    private func applyToneFormattingPreservingLists(
        _ text: String,
        tone: WritingTone,
        languageCode: String
    ) -> String {
        guard !text.isEmpty else { return text }

        let lines = text.components(separatedBy: "\n")
        var chunks: [(isList: Bool, lines: [String])] = []
        chunks.reserveCapacity(max(1, lines.count / 2))

        for line in lines {
            let isList = isListLine(line)
            if var last = chunks.last, last.isList == isList {
                last.lines.append(line)
                chunks[chunks.count - 1] = last
            } else {
                chunks.append((isList: isList, lines: [line]))
            }
        }

        let transformed: [String] = chunks.map { chunk in
            if chunk.isList {
                return chunk.lines
                    .map(normalizeListLine)
                    .joined(separator: "\n")
            }
            let prose = chunk.lines.joined(separator: "\n")
            return applyToneFormattingToProse(prose, tone: tone, languageCode: languageCode)
        }

        return transformed.joined(separator: "\n")
    }

    private func applyToneFormattingToProse(
        _ text: String,
        tone: WritingTone,
        languageCode: String
    ) -> String {
        var result = text
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }

        switch tone {
        case .formal:
            result = insertTransitionSentenceBoundaries(in: result, languageCode: languageCode)
            result = capitalizeSentences(in: result)
            result = applyAutomaticFormalParagraphFormatting(to: result, languageCode: languageCode)

        case .casual:
            result = applyLightPunctuation(to: result, languageCode: languageCode)
            result = capitalizeSentences(in: result)
            result = applyAutomaticFormalParagraphFormatting(to: result, languageCode: languageCode)

        case .veryCasual:
            result = result.lowercased()
            if result.hasSuffix(".") { result = String(result.dropLast()) }
            result = result.replacingOccurrences(of: "[!;:]", with: "", options: .regularExpression)
        }

        return result
    }

    private func isListLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ")
    }

    private func normalizeListLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        let payload: String
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            payload = String(trimmed.dropFirst(2))
        } else {
            payload = trimmed
        }
        let normalized = payload
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -"))
        guard !normalized.isEmpty else { return "" }
        return "- " + normalized.prefix(1).uppercased() + normalized.dropFirst()
    }

    private func insertTransitionSentenceBoundaries(in text: String, languageCode: String) -> String {
        // Uses PunctuationCapitalizationStage's data via a local instance.
        // We duplicate minimal transition boundary logic here for tone formatting.
        let caps = PunctuationCapitalizationStage()
        var result = text
        for rule in caps.transitionBoundaryRules(for: languageCode) {
            let range = NSRange(result.startIndex..., in: result)
            result = rule.regex.stringByReplacingMatches(
                in: result, range: range, withTemplate: rule.replacement
            )
        }
        return result
    }

    private func applyLightPunctuation(to text: String, languageCode: String) -> String {
        var result = insertTransitionSentenceBoundaries(in: text, languageCode: languageCode)
        if let first = result.first {
            result = first.uppercased() + result.dropFirst()
        }
        let wordCount = result.split(separator: " ").count
        if wordCount >= 5, let last = result.last, !".!?".contains(last) {
            result += "."
        }
        return result
    }

    private func capitalizeSentences(in text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = ""
        var shouldCapitalize = true
        for ch in text {
            if shouldCapitalize, ch.isLetter {
                result.append(contentsOf: String(ch).uppercased())
                shouldCapitalize = false
            } else {
                result.append(ch)
            }
            if ".!?".contains(ch) {
                shouldCapitalize = true
            }
        }
        return result
    }

    // MARK: - Paragraph Formatting

    private func applyAutomaticFormalParagraphFormatting(to text: String, languageCode: String) -> String {
        let cleaned = normalizeWhitespacePreservingParagraphs(in: text)
        guard !cleaned.isEmpty else { return cleaned }
        let sentences = sentenceChunks(from: cleaned)
        guard !sentences.isEmpty else { return cleaned }

        let maxSentencesPerParagraph = 3
        let maxWordsPerParagraph = 70
        let maxCharsPerParagraph = 360
        let markers = paragraphBreakMarkers(for: languageCode)

        var paragraphs: [String] = []
        var current: [String] = []
        var currentWords = 0
        var currentChars = 0

        for sentence in sentences {
            let sentenceWords = sentence.split(whereSeparator: \.isWhitespace).count
            let sentenceChars = sentence.count
            let startsMarker = startsWithParagraphBreakMarker(sentence, markers: markers)
            let shouldBreakBefore = !current.isEmpty && (
                startsMarker ||
                current.count >= maxSentencesPerParagraph ||
                currentWords + sentenceWords > maxWordsPerParagraph ||
                currentChars + sentenceChars > maxCharsPerParagraph
            )
            if shouldBreakBefore {
                paragraphs.append(current.joined(separator: " "))
                current = []
                currentWords = 0
                currentChars = 0
            }
            current.append(sentence)
            currentWords += sentenceWords
            currentChars += sentenceChars
        }
        if !current.isEmpty {
            paragraphs.append(current.joined(separator: " "))
        }
        return paragraphs.joined(separator: "\n\n")
    }

    private func sentenceChunks(from text: String) -> [String] {
        var chunks: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.bySentences, .localized]) { substring, _, _, _ in
            guard let raw = substring else { return }
            let sentence = raw
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                chunks.append(sentence)
            }
        }
        if !chunks.isEmpty { return chunks }
        let fallback = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? [] : [fallback]
    }

    private func paragraphBreakMarkers(for languageCode: String) -> [String] {
        switch languageCode.lowercased() {
        case "fr": return ["de plus", "en outre", "par ailleurs", "cependant", "toutefois", "enfin", "en conclusion", "cordialement", "bien à vous"]
        case "en": return ["moreover", "furthermore", "however", "therefore", "meanwhile", "in conclusion", "best regards", "kind regards", "sincerely"]
        case "es": return ["además", "sin embargo", "por lo tanto", "mientras tanto", "en conclusión", "saludos"]
        case "zh": return ["此外", "另外", "然而", "因此", "总之", "最后", "此致", "敬礼"]
        case "ja": return ["さらに", "一方で", "しかし", "そのため", "結論として", "最後に", "よろしくお願いいたします"]
        case "ru": return ["кроме того", "однако", "поэтому", "между тем", "в заключение", "с уважением"]
        case "de": return ["außerdem", "jedoch", "deshalb", "inzwischen", "abschließend", "mit freundlichen grüßen"]
        case "it": return ["inoltre", "tuttavia", "pertanto", "nel frattempo", "in conclusione", "cordiali saluti"]
        case "pt": return ["além disso", "no entanto", "portanto", "enquanto isso", "em conclusão", "atenciosamente"]
        default: return ["however", "therefore", "in conclusion", "best regards", "sincerely"]
        }
    }

    private func startsWithParagraphBreakMarker(_ sentence: String, markers: [String]) -> Bool {
        let normalized = sentence
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'\u{201c}\u{201d}\u{2018}\u{2019}([{"))
        return markers.contains { normalized.hasPrefix($0) }
    }

    // MARK: - Code Formatting

    private func applyCodeFormatting(_ text: String, metadata: PipelineMetadata) -> String {
        switch metadata.formattingMode {
        case .trigger:
            return codeFormatter.formatTranscribedText(text, defaultStyle: metadata.defaultCodeStyle)
        case .advanced:
            return codeFormatter.formatAdvanced(text, defaultStyle: metadata.defaultCodeStyle)
        }
    }

    // MARK: - Whitespace Normalization

    func normalizeWhitespacePreservingParagraphs(in text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: "\\r\\n?", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        normalized = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Stage 5: Contextual Rewrite (Model-Based, Optional)

/// Optional LLM-based rewrite. Only runs when Pro mode is unlocked AND LLM is loaded.
/// Fail-closed: any integrity check failure returns the deterministic input unchanged.
@MainActor
struct ContextualRewriteStage: PipelineStage {
    let name = "ContextualRewrite"
    let isModelBased = true

    private let proTextFormatter = ProTextFormatter()
    private static let log = Logger(subsystem: "com.zphyr.app", category: "Pipeline.Rewrite")

    func process(_ input: StageIO) async -> StageIO {
        guard !input.text.isEmpty else { return input }
        let meta = input.metadata

        // Gate: only run if Pro mode is unlocked AND the LLM is loaded
        guard meta.formattingMode == .advanced,
              meta.isProModeUnlocked,
              meta.isLLMLoaded else {
            Self.log.notice("[Pipeline.Rewrite] skipped: formattingMode=\(meta.formattingMode.rawValue, privacy: .public) pro=\(meta.isProModeUnlocked, privacy: .public) llm=\(meta.isLLMLoaded, privacy: .public)")
            return input
        }

        // Use the deterministic text as both normalizedText (for fallback)
        // and rawASRText (for integrity comparison)
        let context = TextFormatterContext(
            rawASRText: input.text,
            normalizedText: input.text,
            languageCode: meta.languageCode,
            defaultCodeStyle: meta.defaultCodeStyle,
            preferredMode: meta.formattingMode
        )

        AppState.shared.dictationState = .formatting

        let result = await proTextFormatter.format(context)

        // Additional length ratio safeguard: output shouldn't balloon
        let lengthRatio = Double(result.text.count) / max(1.0, Double(input.text.count))
        if lengthRatio > 1.5 {
            Self.log.warning("[Pipeline.Rewrite] rejected: output length ratio \(lengthRatio, privacy: .public) exceeds 1.5x")
            return input
        }

        if result.usedDeterministicFallback {
            Self.log.notice("[Pipeline.Rewrite] integrity check failed — using deterministic output")
            return input
        }

        Self.log.notice("[Pipeline.Rewrite] accepted LLM output len=\(result.text.count, privacy: .public)")
        return input.withText(result.text)
    }
}

// MARK: - Stage 6: Command Extraction (Non-Abort)

/// Detects non-abort spoken commands and strips them from the text.
/// Abort commands are handled by the pipeline pre-scan, not here.
@MainActor
struct CommandExtractionStage: PipelineStage {
    let name = "CommandExtraction"

    func process(_ input: StageIO) -> StageIO {
        guard !input.text.isEmpty else { return input }

        let (command, cleanedText) = CommandInterpreter.shared.extractNonAbort(
            input.text, languageCode: input.metadata.languageCode
        )

        if command != .none {
            return input.withCommand(command, text: cleanedText)
        }

        return input
    }
}

// MARK: - Stage 7: Final Insertion Safety

/// Final cleanup: trim, Unicode normalization, collapse residual spaces.
/// Output is safe for clipboard/insertion.
@MainActor
struct FinalSafetyStage: PipelineStage {
    let name = "FinalSafety"

    func process(_ input: StageIO) -> StageIO {
        guard !input.text.isEmpty else { return input }

        var text = input.text

        // Unicode NFC for clipboard/accessibility compatibility
        text = text.precomposedStringWithCanonicalMapping

        // Collapse any residual double spaces
        text = text.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)

        // Final trim
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        return input.withText(text)
    }
}
