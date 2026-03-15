//
//  SmartTextFormatter.swift
//  Zphyr
//
//  Non-destructive structural analysis for post-processing:
//  1) Repetition cleanup
//  2) Spoken list annotation (without dropping narrative text)
//

import Foundation

final class SmartTextFormatter {
    private let repetitionRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(\w{2,})(?:\s+\1){1,3}\b"#
    )
    private var listRegexCache: [String: NSRegularExpression] = [:]

    struct DetectedListBlock: Sendable, Equatable {
        /// UTF-16 start offset in `Result.cleanedText`.
        let sourceStart: Int
        /// UTF-16 end offset in `Result.cleanedText` (exclusive).
        let sourceEnd: Int
        let items: [String]
        let confidence: Double
    }

    struct Result: Sendable, Equatable {
        let cleanedText: String
        let detectedListBlocks: [DetectedListBlock]
        let listDetectionApplied: Bool
    }

    func run(_ text: String, languageCode: String) -> Result {
        var cleaned = removeRepetitions(in: text)
        cleaned = cleaned
            .replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let blocks = detectListBlocks(in: cleaned, languageCode: languageCode)
        return Result(
            cleanedText: cleaned,
            detectedListBlocks: blocks,
            listDetectionApplied: !blocks.isEmpty
        )
    }

    // MARK: - 1. Repetition removal

    func removeRepetitions(in text: String) -> String {
        guard let regex = repetitionRegex else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1")
    }

    // MARK: - 2. List detection (annotative)

    private typealias MarkerSet = (first: [String], middle: [String], last: [String])

    private func markerSets(for lang: String) -> MarkerSet {
        switch lang {
        case "fr":
            return (
                first: [
                    "d'abord", "premièrement", "primo", "tout d'abord",
                    "pour commencer", "en premier lieu", "en premier", "premier point",
                    "avant tout"
                ],
                middle: [
                    "ensuite", "puis", "deuxièmement", "secundo",
                    "deuxième", "en deuxième", "deuxième point", "troisième", "troisième point",
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
                first:  ["first", "firstly", "to begin with", "first of all", "for starters", "initially", "first point"],
                middle: ["then", "next", "secondly", "after that", "furthermore", "also", "additionally", "thirdly", "third point"],
                last:   ["finally", "lastly", "in conclusion", "to conclude", "to wrap up", "last"]
            )
        }
    }

    private func detectListBlocks(in text: String, languageCode: String) -> [DetectedListBlock] {
        guard !text.isEmpty, let regex = listRegex(for: languageCode) else { return [] }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: fullRange)
        guard matches.count >= 2 else { return [] }

        let grouped = groupListMarkers(matches, in: text)
        guard !grouped.isEmpty else { return [] }

        let markerSets = markerSets(for: languageCode)
        let firstSet = Set(markerSets.first.map(normalizedMarker))
        let middleSet = Set(markerSets.middle.map(normalizedMarker))
        let lastSet = Set(markerSets.last.map(normalizedMarker))
        var blocks: [DetectedListBlock] = []
        blocks.reserveCapacity(grouped.count)

        for (groupIndex, group) in grouped.enumerated() where group.count >= 2 {
            let groupUpperBound: Int = {
                if groupIndex + 1 < grouped.count, let nextFirst = grouped[groupIndex + 1].first {
                    return nextFirst.range.location
                }
                return nsText.length
            }()

            let groupMarkerTexts = group.compactMap { match -> String? in
                guard match.numberOfRanges >= 2 else { return nil }
                let markerRange = match.range(at: 1)
                guard markerRange.location != NSNotFound, markerRange.length > 0 else { return nil }
                return normalizedMarker(nsText.substring(with: markerRange))
            }
            let hasFirstMarker = groupMarkerTexts.contains { firstSet.contains($0) }
            let hasLastMarker = groupMarkerTexts.contains { lastSet.contains($0) }
            let hasMiddleMarker = groupMarkerTexts.contains { middleSet.contains($0) }
            let uniqueMarkerCount = Set(groupMarkerTexts).count
            if !hasFirstMarker && !hasLastMarker && (!hasMiddleMarker || group.count < 3) {
                continue
            }
            if uniqueMarkerCount == 1 && group.count < 3 {
                continue
            }

            var items: [String] = []
            items.reserveCapacity(group.count)
            var blockEnd = group.last?.range.location ?? groupUpperBound
            var foundLastMarker = false

            for markerIndex in 0..<group.count {
                if foundLastMarker { break }
                let marker = group[markerIndex]
                let itemStart = marker.range.location + marker.range.length
                let itemEnd: Int
                if markerIndex + 1 < group.count {
                    itemEnd = group[markerIndex + 1].range.location
                } else {
                    itemEnd = likelyListTailEnd(in: nsText, from: itemStart, upperBound: groupUpperBound)
                }
                blockEnd = max(blockEnd, itemEnd)
                guard itemEnd > itemStart else { continue }
                let rawItem = nsText.substring(with: NSRange(location: itemStart, length: itemEnd - itemStart))
                guard let cleanedItem = normalizedListItem(rawItem), cleanedItem.count >= 2 else { continue }
                items.append(cleanedItem)

                // Stop after the first "last" marker — following markers are narrative text
                if marker.numberOfRanges >= 2 {
                    let markerText = normalizedMarker(nsText.substring(with: marker.range(at: 1)))
                    if lastSet.contains(markerText) { foundLastMarker = true }
                }
            }

            guard items.count >= 2, let firstMarker = group.first else { continue }
            let start = firstMarker.range.location
            guard blockEnd > start else { continue }

            let confidence = blockConfidence(group: group, markerSets: markerSets, itemCount: items.count)
            blocks.append(
                DetectedListBlock(
                    sourceStart: start,
                    sourceEnd: min(blockEnd, nsText.length),
                    items: items,
                    confidence: confidence
                )
            )
        }

        return blocks
    }

    private func groupListMarkers(_ markers: [NSTextCheckingResult], in text: String) -> [[NSTextCheckingResult]] {
        guard !markers.isEmpty else { return [] }
        let nsText = text as NSString
        let maxGap = 260
        var groups: [[NSTextCheckingResult]] = [[markers[0]]]

        for marker in markers.dropFirst() {
            guard var current = groups.popLast() else { break }
            let previous = current[current.count - 1]
            let previousEnd = previous.range.location + previous.range.length
            let gap = marker.range.location - previousEnd
            let betweenRange = NSRange(location: previousEnd, length: max(0, gap))
            let between = betweenRange.length > 0 ? nsText.substring(with: betweenRange) : ""
            let hasHardBreak = between.contains("\n\n")
            if gap > maxGap || hasHardBreak {
                groups.append(current)
                groups.append([marker])
                continue
            }
            current.append(marker)
            groups.append(current)
        }
        return groups
    }

    private func likelyListTailEnd(in text: NSString, from start: Int, upperBound: Int) -> Int {
        guard start < upperBound else { return start }
        var index = start
        while index < upperBound {
            let ch = text.character(at: index)
            if ch == 46 || ch == 33 || ch == 63 || ch == 10 { // . ! ? \n
                return index + 1
            }
            index += 1
        }
        return upperBound
    }

    private func normalizedListItem(_ text: String) -> String? {
        let collapsed = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;: -"))
        guard !collapsed.isEmpty else { return nil }
        return collapsed.prefix(1).uppercased() + collapsed.dropFirst()
    }

    private func blockConfidence(
        group: [NSTextCheckingResult],
        markerSets: MarkerSet,
        itemCount: Int
    ) -> Double {
        let familySignal = markerSets.first.count + markerSets.middle.count + markerSets.last.count

        let markerCount = group.count
        var confidence = 0.45 + min(0.35, Double(itemCount) * 0.08)
        if markerCount >= 3 { confidence += 0.08 }
        if markerCount >= 4 { confidence += 0.05 }
        if familySignal >= 8 { confidence += 0.02 }
        return max(0.0, min(1.0, confidence))
    }

    private func normalizedMarker(_ marker: String) -> String {
        marker
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func listRegex(for languageCode: String) -> NSRegularExpression? {
        if let cached = listRegexCache[languageCode] {
            return cached
        }
        let sets = markerSets(for: languageCode)
        let allMarkers = (sets.first + sets.middle + sets.last)
            .sorted { $0.count > $1.count }

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
