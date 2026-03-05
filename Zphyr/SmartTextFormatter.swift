//
//  SmartTextFormatter.swift
//  Zphyr
//
//  On-device intelligent text post-processing pipeline — pure Swift, zero network.
//
//  Steps (in order):
//    1. Word-repetition removal   ("voilà voilà" → "voilà")
//    2. TODO / action extraction  → checklist strings
//    3. Spoken-list detection     → markdown bullet list
//

import Foundation

final class SmartTextFormatter {
    private let repetitionRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(\w{2,})(?:\s+\1){1,3}\b"#
    )
    private var todoRegexCache: [String: [NSRegularExpression]] = [:]
    private var listRegexCache: [String: NSRegularExpression] = [:]

    // MARK: - Result

    struct Result {
        let text: String        // cleaned main body (may be empty if everything became todos)
        let todos: [String]     // extracted task strings, no "- [ ]" prefix
        let isList: Bool        // true → text is already bullet-formatted
    }

    // MARK: - Entry point

    func run(_ text: String, languageCode: String) -> Result {
        var result = text

        // 1. Word repetitions
        result = removeRepetitions(in: result)

        // 2. TODO extraction (before list detection to avoid interference)
        let (todos, afterTodos) = extractTodos(from: result, languageCode: languageCode)
        result = afterTodos

        // 3. List detection on whatever remains
        if let list = detectAndFormatList(in: result, languageCode: languageCode) {
            return Result(text: list, todos: todos, isList: true)
        }

        return Result(text: result, todos: todos, isList: false)
    }

    // MARK: - 1. Repetition removal

    /// Removes a word that is immediately repeated 1–3 times.
    /// e.g. "voilà voilà voilà" → "voilà", "ok ok" → "ok"
    func removeRepetitions(in text: String) -> String {
        guard let regex = repetitionRegex else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1")
    }

    // MARK: - 2. TODO extraction

    private func todoPatterns(for lang: String) -> [String] {
        switch lang {
        case "fr":
            return [
                #"(?i)\bpense[rz]?\s+(?:bien\s+)?à\s+([^.!?]+)"#,
                #"(?i)\bn'?oublie\s+pas\s+(?:de\s+)?([^.!?]+)"#,
                #"(?i)\boublie\s+pas\s+(?:de\s+)?([^.!?]+)"#,
                #"(?i)\bil\s+faut\s+(?:que\s+(?:je|on|tu)\s+)?([^.!?]+)"#,
                #"(?i)\bfaut\s+(?:pas\s+oublier\s+(?:de\s+)?|absolument\s+)?([^.!?]+)"#,
                #"(?i)\bje\s+dois\s+(?:absolument\s+|vraiment\s+)?([^.!?]+)"#,
                #"(?i)\bon\s+doit\s+([^.!?]+)"#,
                #"(?i)\bà\s+faire\s*[:\-]\s*([^.!?]+)"#,
                #"(?i)\btodo\s*[:\-]\s*([^.!?]+)"#,
                #"(?i)\brappelle\s*-?\s*(?:moi|toi)\s+(?:de\s+)?([^.!?]+)"#,
                #"(?i)\baction\s*[:\-]\s*([^.!?]+)"#,
            ]
        case "es":
            return [
                #"(?i)\brecuerda\s+(?:de\s+)?([^.!?]+)"#,
                #"(?i)\bno\s+olvides\s+(?:de\s+)?([^.!?]+)"#,
                #"(?i)\bhay\s+que\s+([^.!?]+)"#,
                #"(?i)\bdebo\s+([^.!?]+)"#,
                #"(?i)\btodo\s*[:\-]\s*([^.!?]+)"#,
            ]
        case "de":
            return [
                #"(?i)\bdenke?\s+daran\s+(?:zu\s+)?([^.!?]+)"#,
                #"(?i)\bnicht\s+vergessen\s+(?:zu\s+)?([^.!?]+)"#,
                #"(?i)\bich\s+muss\s+([^.!?]+)"#,
                #"(?i)\btodo\s*[:\-]\s*([^.!?]+)"#,
            ]
        default: // en
            return [
                #"(?i)\bremember\s+to\s+([^.!?]+)"#,
                #"(?i)\bdon'?t\s+forget\s+to\s+([^.!?]+)"#,
                #"(?i)\bneed\s+to\s+([^.!?]+)"#,
                #"(?i)\bmake\s+sure\s+to\s+([^.!?]+)"#,
                #"(?i)\bhave\s+to\s+([^.!?]+)"#,
                #"(?i)\bi\s+should\s+([^.!?]+)"#,
                #"(?i)\btodo\s*[:\-]\s*([^.!?]+)"#,
                #"(?i)\baction\s+item\s*[:\-]\s*([^.!?]+)"#,
            ]
        }
    }

    func extractTodos(from text: String, languageCode: String) -> (todos: [String], cleaned: String) {
        var todos: [String] = []
        var result = text

        for regex in todoRegexes(for: languageCode) {
            let matches = regex.matches(
                in: result,
                range: NSRange(result.startIndex..., in: result)
            )
            for match in matches.reversed() {
                guard match.numberOfRanges >= 2,
                      let captureRange = Range(match.range(at: 1), in: result) else { continue }

                var task = String(result[captureRange])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard task.count > 4 else { continue }

                task = task.prefix(1).uppercased() + task.dropFirst()
                todos.append(task)

                if let fullRange = Range(match.range, in: result) {
                    result.removeSubrange(fullRange)
                }
            }
        }

        result = result
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Deduplicate, preserving original order
        var seen = Set<String>()
        let unique = todos.reversed().filter { seen.insert($0.lowercased()).inserted }.reversed()
        return (Array(unique), result)
    }

    // MARK: - 3. List detection

    private typealias MarkerSet = (first: [String], middle: [String], last: [String])

    private func markerSets(for lang: String) -> MarkerSet {
        switch lang {
        case "fr":
            return (
                first: [
                    "d'abord", "premièrement", "primo", "tout d'abord",
                    "pour commencer", "en premier lieu", "avant tout"
                ],
                middle: [
                    "ensuite", "puis", "deuxièmement", "secundo",
                    "par ailleurs", "également", "d'autre part",
                    "de plus", "en outre"
                ],
                last: [
                    "enfin", "finalement", "pour terminer", "en conclusion",
                    "pour finir", "pour clore", "dernièrement", "au final"
                ]
            )
        case "es":
            return (
                first:  ["primero", "en primer lugar", "para empezar", "ante todo"],
                middle: ["luego", "después", "segundo", "además", "también"],
                last:   ["finalmente", "por último", "para concluir", "en conclusión"]
            )
        case "de":
            return (
                first:  ["erstens", "zunächst", "als erstes", "zu beginn"],
                middle: ["zweitens", "dann", "außerdem", "danach", "weiterhin"],
                last:   ["schließlich", "zuletzt", "abschließend", "zum schluss"]
            )
        default: // en
            return (
                first:  ["first", "firstly", "to begin with", "first of all", "for starters", "initially"],
                middle: ["then", "next", "secondly", "after that", "furthermore", "also", "additionally"],
                last:   ["finally", "lastly", "in conclusion", "to conclude", "to wrap up", "last"]
            )
        }
    }

    func detectAndFormatList(in text: String, languageCode: String) -> String? {
        guard let regex = listRegex(for: languageCode) else { return nil }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: fullRange)
        guard matches.count >= 2 else { return nil }

        // Collect text segments between marker positions
        var segments: [String] = []
        var cursor = text.startIndex

        for (idx, match) in matches.enumerated() {
            guard let matchRange = Range(match.range, in: text) else { continue }

            let before = String(text[cursor..<matchRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
            if !before.isEmpty {
                // Skip preamble before the very first marker
                if idx > 0 { segments.append(before) }
            }
            cursor = matchRange.upperBound
        }

        // Tail after last marker
        let tail = String(text[cursor...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
        if !tail.isEmpty { segments.append(tail) }

        guard segments.count >= 2 else { return nil }

        return segments.compactMap { seg -> String? in
            let s = seg.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { return nil }
            return "- " + s.prefix(1).uppercased() + s.dropFirst()
        }.joined(separator: "\n")
    }

    // MARK: - Helpers

    static func todoBlock(from todos: [String]) -> String {
        todos.map { "- [ ] \($0)" }.joined(separator: "\n")
    }

    private func todoRegexes(for languageCode: String) -> [NSRegularExpression] {
        if let cached = todoRegexCache[languageCode] {
            return cached
        }
        let compiled = todoPatterns(for: languageCode).compactMap { pattern in
            try? NSRegularExpression(pattern: pattern)
        }
        todoRegexCache[languageCode] = compiled
        return compiled
    }

    private func listRegex(for languageCode: String) -> NSRegularExpression? {
        if let cached = listRegexCache[languageCode] {
            return cached
        }
        let sets = markerSets(for: languageCode)
        let allMarkers = (sets.first + sets.middle + sets.last)
            .sorted { $0.count > $1.count }   // longest first avoids partial overlaps

        let escaped = allMarkers
            .filter { $0.count >= 4 }
            .map { NSRegularExpression.escapedPattern(for: $0) }
        guard !escaped.isEmpty else { return nil }

        let pattern = "(?i)(?:(?:^|[,.]?)\\s+|^)(" + escaped.joined(separator: "|") + ")\\s+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        listRegexCache[languageCode] = regex
        return regex
    }
}
