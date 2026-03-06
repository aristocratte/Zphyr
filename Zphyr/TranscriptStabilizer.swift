//
//  TranscriptStabilizer.swift
//  Zphyr
//
//  Post-processing pipeline: filler removal → smart structural analysis
//  → tone formatting → dictionary substitutions → snippet injection.
//  All processing is deterministic and runs on-device.
//

import Foundation
import AppKit

// TODO: [STREAMING] For live corrections, stabilize() will need to run on partial
// transcript segments. Factor regex caches out as @Sendable for concurrent use.

/// Determines the `WritingTone` for the app that was frontmost during recording.
func activeTone(bundleID: String?) -> WritingTone {
    let state = AppState.shared
    guard let bundleID else {
        return state.styleOther
    }
    // Mail clients → email tone
    if bundleID.contains("mail") || bundleID.contains("Mail") ||
       bundleID.contains("mimestream") || bundleID.contains("Airmail") ||
       bundleID.contains("Spark") {
        return state.styleEmail
    }
    // Messaging apps → personal tone
    if bundleID.contains("Messages") || bundleID.contains("WhatsApp") ||
       bundleID.contains("Telegram") || bundleID.contains("Signal") ||
       bundleID.contains("Discord") {
        return state.stylePersonal
    }
    // Work / productivity apps → work tone
    if bundleID.contains("Slack") || bundleID.contains("Teams") ||
       bundleID.contains("notion") || bundleID.contains("Linear") ||
       bundleID.contains("Jira") || bundleID.contains("Confluence") ||
       bundleID.contains("zoom") || bundleID.contains("Zoom") {
        return state.styleWork
    }
    return state.styleOther
}

@MainActor
final class TranscriptStabilizer {

    struct Result {
        let text: String
        let listBlocksCount: Int
    }

    // MARK: - Regex Caches

    private var fillerRegexCache: [String: [NSRegularExpression]] = [:]
    private var transitionRuleCache: [String: [TransitionBoundaryRule]] = [:]
    private var formalPunctuationRuleCache: [String: [(regex: NSRegularExpression, replacement: String)]] = [:]

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

    private let spaceBeforePunctuationRegex = try? NSRegularExpression(pattern: "\\s+([,;:.!?\\)])")
    private let missingSpaceAfterPunctuationRegex = try? NSRegularExpression(pattern: "([,;:.!?])([^\\s])")
    private let spaceAfterOpenParenRegex = try? NSRegularExpression(pattern: "\\(\\s+")
    private let dashSpacingRegex = try? NSRegularExpression(pattern: "\\s*—\\s*")

    private let smartFormatter = SmartTextFormatter()

    private struct TransitionBoundaryRule {
        let regex: NSRegularExpression
        let replacement: String
    }

    // MARK: - Public API

    /// Full stabilization pipeline.
    /// targetBundleID is the bundle identifier of the app that was frontmost during recording.
    func stabilize(
        _ rawText: String,
        targetBundleID: String?,
        tone: WritingTone
    ) -> Result {
        guard !rawText.isEmpty else {
            return Result(text: rawText, listBlocksCount: 0)
        }
        let languageCode = AppState.shared.selectedLanguage.id

        // ── Phase A: non-destructive cleanup ───────────────────────────────────
        var cleaned = rawText
        for regex in fillerRemovalRegexes(for: languageCode) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
        }
        cleaned = cleaned
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let smart = smartFormatter.run(cleaned, languageCode: languageCode)
        cleaned = smart.cleanedText
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // ── Phase B: structural annotation → mixed text + inline lists ────────
        var result = Self.renderDetectedListBlocksInline(cleaned, blocks: smart.detectedListBlocks)

        // Keep contextual substitutions after list rendering (ranges are based on cleaned text).
        result = applyDictionaryPronunciationMappings(to: result)
        result = applyContextualLinkSnippets(to: result, bundleID: targetBundleID)

        // ── Phase C: tone formatting with list-line preservation ───────────────
        result = applyToneFormattingPreservingLists(result, tone: tone, languageCode: languageCode)
        result = normalizeWhitespacePreservingParagraphs(in: result)

        return Result(
            text: result,
            listBlocksCount: smart.detectedListBlocks.count
        )
    }

    // MARK: - List Block Rendering

    nonisolated static func renderDetectedListBlocksInline(
        _ text: String,
        blocks: [SmartTextFormatter.DetectedListBlock]
    ) -> String {
        guard !blocks.isEmpty else { return text }
        var result = text
        let sorted = blocks.sorted { $0.sourceStart > $1.sourceStart }

        for block in sorted {
            let nsResult = result as NSString
            let location = block.sourceStart
            let length = block.sourceEnd - block.sourceStart
            guard location >= 0, length > 0, location + length <= nsResult.length else { continue }

            let replacementLines = block.items.compactMap { item -> String? in
                let normalized = item
                    .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { return nil }
                return "- " + normalized
            }
            guard !replacementLines.isEmpty else { continue }

            var replacement = replacementLines.joined(separator: "\n")
            if location > 0 {
                let previousChar = nsResult.substring(with: NSRange(location: location - 1, length: 1))
                if previousChar != "\n" {
                    replacement = "\n" + replacement
                }
            }
            if location + length < nsResult.length {
                let nextChar = nsResult.substring(with: NSRange(location: location + length, length: 1))
                if nextChar != "\n" {
                    replacement += "\n"
                }
            }

            let range = NSRange(location: location, length: length)
            result = nsResult.replacingCharacters(in: range, with: replacement)
        }
        return result
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
            result = applyFormalPunctuation(to: result, languageCode: languageCode)
            result = insertTransitionSentenceBoundaries(in: result, languageCode: languageCode)
            result = capitalizeSentences(in: result)
            result = applyAutomaticFormalParagraphFormatting(to: result, languageCode: languageCode)

        case .casual:
            result = applyLightPunctuation(to: result, languageCode: languageCode)
            result = capitalizeSentences(in: result)
            // Keep casual tone but still split dense dictation into readable paragraphs.
            result = applyAutomaticFormalParagraphFormatting(to: result, languageCode: languageCode)

        case .veryCasual:
            result = result.lowercased()
            if result.hasSuffix(".") { result = String(result.dropLast()) }
            result = result.replacingOccurrences(of: "[!;:]", with: "", options: .regularExpression)
        }

        return result
    }

    // MARK: - List Helpers

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

    // MARK: - Transition Boundaries

    private func insertTransitionSentenceBoundaries(in text: String, languageCode: String) -> String {
        var result = text
        for rule in transitionBoundaryRules(for: languageCode) {
            let range = NSRange(result.startIndex..., in: result)
            result = rule.regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: rule.replacement
            )
        }
        return result
    }

    // MARK: - Punctuation

    private func applyLightPunctuation(to text: String, languageCode: String) -> String {
        var result = insertTransitionSentenceBoundaries(in: text, languageCode: languageCode)

        // Capitalise first letter
        if let first = result.first {
            result = first.uppercased() + result.dropFirst()
        }

        // Add closing period to substantial texts (>= 5 words) that lack one
        let wordCount = result.split(separator: " ").count
        if wordCount >= 5, let last = result.last, !".!?".contains(last) {
            result += "."
        }

        return result
    }

    private func applyFormalPunctuation(to text: String, languageCode: String) -> String {
        var result = text

        for item in formalPunctuationRules(for: languageCode) {
            let range = NSRange(result.startIndex..., in: result)
            result = item.regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: item.replacement
            )
        }

        // Remove spaces before punctuation.
        if let spaceBeforePunctuationRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = spaceBeforePunctuationRegex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "$1"
            )
        }
        // Ensure one space after punctuation when followed by text.
        if let missingSpaceAfterPunctuationRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = missingSpaceAfterPunctuationRegex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "$1 $2"
            )
        }
        // Normalize spaces around opening parenthesis and em dash.
        if let spaceAfterOpenParenRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = spaceAfterOpenParenRegex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "("
            )
        }
        if let dashSpacingRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = dashSpacingRegex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: " — "
            )
        }

        result = result
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // If the user did not dictate final punctuation, close sentence with a period.
        if let last = result.last, !".!?".contains(last) {
            result += "."
        }

        return result
    }

    // MARK: - Capitalization

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

    private func capitalizeProperNouns(in text: String) -> String {
        var result = text
        for rule in properNounRules {
            let range = NSRange(result.startIndex..., in: result)
            result = rule.regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: rule.replacement
            )
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
        if !chunks.isEmpty {
            return chunks
        }

        let fallback = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? [] : [fallback]
    }

    private func paragraphBreakMarkers(for languageCode: String) -> [String] {
        switch languageCode.lowercased() {
        case "fr":
            return ["de plus", "en outre", "par ailleurs", "cependant", "toutefois", "enfin", "en conclusion", "cordialement", "bien à vous"]
        case "en":
            return ["moreover", "furthermore", "however", "therefore", "meanwhile", "in conclusion", "best regards", "kind regards", "sincerely"]
        case "es":
            return ["además", "sin embargo", "por lo tanto", "mientras tanto", "en conclusión", "saludos"]
        case "zh":
            return ["此外", "另外", "然而", "因此", "总之", "最后", "此致", "敬礼"]
        case "ja":
            return ["さらに", "一方で", "しかし", "そのため", "結論として", "最後に", "よろしくお願いいたします"]
        case "ru":
            return ["кроме того", "однако", "поэтому", "между тем", "в заключение", "с уважением"]
        case "de":
            return ["außerdem", "jedoch", "deshalb", "inzwischen", "abschließend", "mit freundlichen grüßen"]
        case "it":
            return ["inoltre", "tuttavia", "pertanto", "nel frattempo", "in conclusione", "cordiali saluti"]
        case "pt":
            return ["além disso", "no entanto", "portanto", "enquanto isso", "em conclusão", "atenciosamente"]
        default:
            return ["however", "therefore", "in conclusion", "best regards", "sincerely"]
        }
    }

    private func startsWithParagraphBreakMarker(_ sentence: String, markers: [String]) -> Bool {
        let normalized = sentence
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'\u{201c}\u{201d}\u{2018}\u{2019}([{"))
        return markers.contains { normalized.hasPrefix($0) }
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

    // MARK: - Dictionary Mappings

    private func applyDictionaryPronunciationMappings(to text: String) -> String {
        var result = text

        for rule in DictionaryStore.shared.pronunciationReplacementRules {
            let range = NSRange(result.startIndex..., in: result)
            result = rule.regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: rule.replacementTemplate
            )
        }

        return result
    }

    // MARK: - Contextual Snippets

    private enum SnippetContext {
        case email
        case social
        case general
    }

    private struct ContextualSnippetRule {
        let pattern: String
        let replacement: String
    }

    private func applyContextualLinkSnippets(to text: String, bundleID: String?) -> String {
        var result = text
        let languageCode = AppState.shared.selectedLanguage.id
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
                ContextualSnippetRule(
                    pattern: snippetPattern(for: $0),
                    replacement: linkedInReplacement
                )
            })
        }
        if flags.socialEnabled {
            rules.append(contentsOf: triggers.social.map {
                ContextualSnippetRule(
                    pattern: snippetPattern(for: $0),
                    replacement: socialReplacement
                )
            })
        }
        if flags.gmailEnabled {
            rules.append(contentsOf: triggers.gmail.map {
                ContextualSnippetRule(
                    pattern: snippetPattern(for: $0),
                    replacement: mailReplacement
                )
            })
        }

        for rule in rules {
            let replacement = "$1\(escapedRegexReplacement(rule.replacement))"
            result = result.replacingOccurrences(
                of: rule.pattern,
                with: replacement,
                options: .regularExpression
            )
        }

        return result
    }

    private func snippetContext(for bundleID: String?) -> SnippetContext {
        guard let bundleID else { return .general }
        let lower = bundleID.lowercased()

        // Email compose contexts
        if lower.contains("mail") ||
            lower.contains("outlook") ||
            lower.contains("mimestream") ||
            lower.contains("spark") ||
            lower.contains("airmail") {
            return .email
        }

        // Social media contexts
        if lower.contains("linkedin") ||
            lower.contains("twitter") ||
            lower.contains("facebook") ||
            lower.contains("instagram") ||
            lower.contains("threads") {
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
        raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "$", with: "\\$")
    }

    private func snippetFeatureFlags() -> (
        linkedInEnabled: Bool,
        socialEnabled: Bool,
        gmailEnabled: Bool,
        verboseInEmail: Bool
    ) {
        let defaults = UserDefaults.standard
        let linkedInEnabled = defaults.object(forKey: AppState.snippetLinkedInEnabledKey) == nil
            ? true
            : defaults.bool(forKey: AppState.snippetLinkedInEnabledKey)
        let socialEnabled = defaults.object(forKey: AppState.snippetSocialEnabledKey) == nil
            ? true
            : defaults.bool(forKey: AppState.snippetSocialEnabledKey)
        let gmailEnabled = defaults.object(forKey: AppState.snippetGmailEnabledKey) == nil
            ? true
            : defaults.bool(forKey: AppState.snippetGmailEnabledKey)
        let verboseInEmail = defaults.object(forKey: AppState.snippetVerboseInEmailKey) == nil
            ? true
            : defaults.bool(forKey: AppState.snippetVerboseInEmailKey)
        return (linkedInEnabled, socialEnabled, gmailEnabled, verboseInEmail)
    }

    private func cleanedSnippetValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    // MARK: - Filler & Transition Data

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

    private func transitionBoundaryRules(for languageCode: String) -> [TransitionBoundaryRule] {
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
}
