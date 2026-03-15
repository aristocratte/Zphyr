//
//  CommandInterpreter.swift
//  Zphyr
//
//  Detects spoken meta-commands in the transcript (e.g. "annule" / "cancel that",
//  "copie dans le presse-papiers" / "copy to clipboard").
//
//  Two entry points:
//   • scanForAbort()    — pre-pipeline scan for abort commands (cancel, undo)
//   • extractNonAbort() — post-pipeline extraction of non-abort commands
//

import Foundation

enum RecognizedCommand: Equatable {
    case none
    case cancelLast
    case copyOnly
    case forceList
    case newParagraph
    case customAction(String)
}

struct CommandInterpreter {
    static let shared = CommandInterpreter()

    // MARK: - Pre-Pipeline Abort Scan

    /// Scans for abort commands before any pipeline processing.
    /// These commands short-circuit the entire pipeline.
    /// Returns (.none, fullText) if no abort command found.
    func scanForAbort(_ transcript: String, languageCode: String) -> (command: RecognizedCommand, cleanedText: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        let cancelPhrases = abortPhrases(for: languageCode)

        // Pass 1: Exact full match and suffix match
        for phrase in cancelPhrases {
            // Entire utterance is the abort command
            if lower == phrase {
                return (.cancelLast, "")
            }
            // Abort command at the end — strip it, return content before
            if lower.hasSuffix(" " + phrase) || lower.hasSuffix("," + phrase) || lower.hasSuffix(", " + phrase) {
                let endIndex = lower.range(of: phrase, options: .backwards)!.lowerBound
                let remaining = String(trimmed[trimmed.startIndex..<endIndex])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ","))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (.cancelLast, remaining)
            }
        }

        // Pass 2: Abort phrase embedded mid-utterance with content before it.
        // Fires only when:
        //   (a) the content before the phrase is entirely filler/hesitation words, OR
        //   (b) the content after the phrase contains another abort phrase.
        // This catches e.g. "send this to Jean cancel never mind actually send it"
        // without false-positiving on "I need to cancel the appointment".
        let fillerWords: Set<String> = [
            "wait", "actually", "um", "uh", "hmm", "so", "like", "well", "okay", "ok", "right", "just"
        ]
        for phrase in cancelPhrases {
            let escaped = NSRegularExpression.escapedPattern(for: phrase)
            guard let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b"),
                  let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
                  let range = Range(match.range, in: lower) else { continue }

            // Must have content before the phrase (not at utterance start)
            guard range.lowerBound != lower.startIndex else { continue }

            let before = String(trimmed[trimmed.startIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let after = String(lower[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Condition (a): everything before is filler
            let beforeWords = before.lowercased().split(separator: " ").map(String.init)
            let beforeAllFillers = !beforeWords.isEmpty && beforeWords.allSatisfy { fillerWords.contains($0) }

            // Condition (b): content after contains another abort phrase
            let afterHasAbort = cancelPhrases.contains { p in after.contains(p) }

            guard beforeAllFillers || afterHasAbort else { continue }

            let contentBefore = beforeAllFillers ? "" : before
                .trimmingCharacters(in: CharacterSet(charactersIn: ","))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (.cancelLast, contentBefore)
        }

        return (.none, transcript)
    }

    // MARK: - Post-Pipeline Non-Abort Extraction

    /// Extracts non-abort commands from the formatted text.
    /// Returns (.none, fullText) if no command is found.
    func extractNonAbort(_ transcript: String, languageCode: String) -> (command: RecognizedCommand, cleanedText: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // New paragraph
        let paragraphPhrases = newParagraphPhrases(for: languageCode)
        for phrase in paragraphPhrases {
            if lower == phrase {
                return (.newParagraph, "\n\n")
            }
            if let range = findPhraseBoundary(phrase, in: trimmed) {
                var cleaned = trimmed
                cleaned.removeSubrange(range)
                cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ","))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // Insert paragraph break where the command was
                if range.lowerBound == trimmed.startIndex {
                    cleaned = "\n\n" + cleaned
                } else {
                    let before = String(trimmed[trimmed.startIndex..<range.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let after = String(trimmed[range.upperBound...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    cleaned = before + "\n\n" + after
                }
                return (.newParagraph, cleaned.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        // Copy only
        let copyPhrases = copyOnlyPhrases(for: languageCode)
        for phrase in copyPhrases {
            if lower == phrase {
                return (.copyOnly, "")
            }
            if let range = findPhraseBoundary(phrase, in: trimmed) {
                var cleaned = trimmed
                cleaned.removeSubrange(range)
                cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ","))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (.copyOnly, cleaned)
            }
        }

        // Force list
        let listPhrases = forceListPhrases(for: languageCode)
        for phrase in listPhrases {
            if lower == phrase || lower.hasPrefix(phrase + " ") || lower.hasPrefix(phrase + ",") {
                let after = String(trimmed.dropFirst(phrase.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ","))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (.forceList, after)
            }
        }

        return (.none, transcript)
    }

    // MARK: - Legacy API (backward compatibility)

    /// Original API — scans for all commands. Used by CommandExtractionStage.
    func interpret(_ transcript: String, languageCode: String) -> (command: RecognizedCommand, cleanedText: String) {
        // Try abort first
        let (abortCmd, abortCleaned) = scanForAbort(transcript, languageCode: languageCode)
        if abortCmd != .none { return (abortCmd, abortCleaned) }

        // Then try non-abort
        return extractNonAbort(transcript, languageCode: languageCode)
    }

    // MARK: - Phrase Matching

    private func findPhraseBoundary(_ phrase: String, in text: String) -> Range<String.Index>? {
        let lower = text.lowercased()
        guard let range = lower.range(of: phrase) else { return nil }

        // Verify word boundaries
        if range.lowerBound != lower.startIndex {
            let charBefore = lower[lower.index(before: range.lowerBound)]
            if charBefore.isLetter || charBefore.isNumber { return nil }
        }
        if range.upperBound != lower.endIndex {
            let charAfter = lower[range.upperBound]
            if charAfter.isLetter || charAfter.isNumber { return nil }
        }

        // Only match at the START or END of the utterance.
        // Matching command phrases embedded in the middle of natural speech
        // causes false positives (e.g. "I'll copy that" triggers copyOnly).
        let isAtStart = range.lowerBound == lower.startIndex
        let isAtEnd: Bool = {
            let trailing = String(lower[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
            return trailing.isEmpty
        }()
        guard isAtStart || isAtEnd else { return nil }

        // Map back to original text indices
        return range
    }

    // MARK: - Command Phrase Data

    private func abortPhrases(for languageCode: String) -> [String] {
        switch languageCode {
        case "fr":
            return ["annule", "annuler", "annule ça", "annuler ça", "oublie", "oublie ça", "laisse tomber"]
        case "es":
            return ["cancela", "cancelar", "cancela eso", "olvida", "olvida eso", "borra", "borra eso"]
        case "de":
            return ["abbrechen", "rückgängig", "vergiss das"]
        default:
            return ["cancel", "cancel that", "undo", "undo that", "never mind", "scratch that"]
        }
    }

    private func newParagraphPhrases(for languageCode: String) -> [String] {
        switch languageCode {
        case "fr":
            return ["nouveau paragraphe", "à la ligne", "retour à la ligne",
                    "saut de ligne", "nouvelle ligne"]
        case "es":
            return ["nuevo párrafo", "nueva línea", "salto de línea"]
        case "de":
            return ["neuer absatz", "neue zeile"]
        default:
            return ["new paragraph", "new line", "next paragraph", "line break"]
        }
    }

    private func copyOnlyPhrases(for languageCode: String) -> [String] {
        switch languageCode {
        case "fr":
            return ["copie", "copie ça", "copier", "copie dans le presse-papiers",
                    "copier dans le presse-papiers"]
        case "es":
            return ["copia", "copiar", "copia eso", "copiar al portapapeles"]
        case "de":
            return ["kopieren", "in die zwischenablage"]
        default:
            return ["copy", "copy that", "copy to clipboard", "just copy"]
        }
    }

    private func forceListPhrases(for languageCode: String) -> [String] {
        switch languageCode {
        case "fr":
            return ["formate en liste", "fais une liste", "en liste", "format liste"]
        case "es":
            return ["hacer lista", "formato lista", "en lista"]
        case "de":
            return ["als liste", "liste erstellen"]
        default:
            return ["make a list", "format as list", "as a list", "list format"]
        }
    }
}
