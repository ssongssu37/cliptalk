import Foundation

/// One caption cue in a parsed VTT file. `wordAnchors` pairs (char position in
/// the cue's raw text) with the per-word timestamp YouTube embeds inline.
struct Cue {
    let text: String          // raw cue text (with original casing, punctuation)
    let start: TimeInterval   // cue start
    let end: TimeInterval     // cue end
    /// (charPosInRawText, timestampSec). Present on YouTube auto-captions,
    /// empty on uploaded caption files.
    let wordAnchors: [(Int, TimeInterval)]
}

/// A fully-built searchable caption index: the dedup'd "big text" of the
/// whole video, a per-char map back to the originating cue, and per-char map
/// back to a raw position *inside* that cue (so we can interpolate mid-cue
/// using word anchors).
struct CaptionIndex {
    let cues: [Cue]
    let bigText: String               // normalized, lowercase, dedup'd
    let charToCue: [Int]              // bigText index → index into cues
    let charToRawPos: [Int]           // bigText index → char pos in cue.text
}

/// Result of matching text inside the caption index.
struct ClipRange {
    let start: TimeInterval
    let end: TimeInterval
}

enum CaptionError: LocalizedError {
    case textNotFound(String)

    var errorDescription: String? {
        switch self {
        case .textNotFound(let q):
            let snippet = q.count > 80 ? String(q.prefix(80)) + "…" : q
            return "Text not found in captions: “\(snippet)”"
        }
    }
}

// MARK: - Parser

enum CaptionParser {

    /// Parse raw VTT text into cues. Preserves inline per-word timestamps
    /// (<00:00:05.500>) as `Cue.wordAnchors`.
    static func parse(vtt: String) -> [Cue] {
        var cues: [Cue] = []
        let lines = vtt.components(separatedBy: "\n")
        var i = 0

        let timestampLine = try! NSRegularExpression(
            pattern: #"^(\d+:\d+:\d+\.\d+)\s*-->\s*(\d+:\d+:\d+\.\d+)"#
        )
        let inlineTS = try! NSRegularExpression(pattern: #"<(\d+:\d+:\d+\.\d+)>"#)
        let tagStripper = try! NSRegularExpression(pattern: #"<[^>]*>"#)

        while i < lines.count {
            let line = lines[i]
            let range = NSRange(line.startIndex..., in: line)
            guard let m = timestampLine.firstMatch(in: line, range: range) else {
                i += 1
                continue
            }
            guard let startRange = Range(m.range(at: 1), in: line),
                  let endRange = Range(m.range(at: 2), in: line) else { i += 1; continue }
            let startSec = parseTS(String(line[startRange]))
            let endSec = parseTS(String(line[endRange]))
            i += 1

            // Collect subsequent non-blank lines as this cue's text.
            var rawLines: [String] = []
            while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                rawLines.append(lines[i])
                i += 1
            }
            guard !rawLines.isEmpty else { continue }

            // For each raw line: walk chars, extract inline timestamps into
            // (char_pos_in_flat, time) anchors, and produce a cleaned flat string.
            var flat = ""
            var anchors: [(Int, TimeInterval)] = []

            for rl in rawLines {
                var pos = rl.startIndex
                var chunk = ""

                while pos < rl.endIndex {
                    let sub = rl[pos...]
                    let subNSRange = NSRange(sub.startIndex..<sub.endIndex, in: rl)
                    if let m2 = inlineTS.firstMatch(in: rl, options: .anchored, range: subNSRange) {
                        // Emit accumulated chunk (with tags stripped), then anchor.
                        let cleanedChunk = stripTags(chunk, regex: tagStripper)
                            .replacingOccurrences(of: "&nbsp;", with: " ")
                        flat += cleanedChunk
                        chunk = ""
                        if let tsRange = Range(m2.range(at: 1), in: rl) {
                            let ts = parseTS(String(rl[tsRange]))
                            anchors.append((flat.count, ts))
                        }
                        pos = rl.index(pos, offsetBy: m2.range.length)
                    } else {
                        chunk.append(rl[pos])
                        pos = rl.index(after: pos)
                    }
                }

                let tail = stripTags(chunk, regex: tagStripper)
                    .replacingOccurrences(of: "&nbsp;", with: " ")
                flat += tail
                if !flat.isEmpty && !flat.hasSuffix(" ") { flat += " " }
            }

            flat = flat.trimmingCharacters(in: .whitespaces)
            guard !flat.isEmpty else { continue }

            cues.append(Cue(text: flat, start: startSec, end: endSec, wordAnchors: anchors))
        }

        return cues
    }

    private static func stripTags(_ s: String, regex: NSRegularExpression) -> String {
        let range = NSRange(s.startIndex..., in: s)
        return regex.stringByReplacingMatches(in: s, range: range, withTemplate: "")
    }

    private static func parseTS(_ ts: String) -> TimeInterval {
        let parts = ts.split(separator: ":")
        guard parts.count == 3 else { return 0 }
        let h = TimeInterval(parts[0]) ?? 0
        let m = TimeInterval(parts[1]) ?? 0
        let s = TimeInterval(parts[2]) ?? 0
        return h * 3600 + m * 60 + s
    }
}

// MARK: - Index builder

extension CaptionIndex {

    /// Build the index from a list of cues. Dedupes rolling-caption overlap
    /// (where each new cue restates the end of the previous one).
    static func build(from cues: [Cue]) -> CaptionIndex {
        var bigText = ""
        var charToCue: [Int] = []
        var charToRawPos: [Int] = []

        for (idx, cue) in cues.enumerated() {
            let normText = Self.normalizeStatic(cue.text)
            if normText.isEmpty { continue }

            // How much of this cue's normalized text already appears at the end
            // of bigText? Drop that prefix from this cue.
            var overlap = 0
            let maxCheck = min(bigText.count, normText.count)
            for o in stride(from: maxCheck, to: 0, by: -1) {
                if bigText.hasSuffix(String(normText.prefix(o))) {
                    overlap = o
                    break
                }
            }
            let newText = String(normText.dropFirst(overlap))
            if newText.trimmingCharacters(in: .whitespaces).isEmpty { continue }

            // Inject a space between bigText and the new text if neither has one.
            if !bigText.isEmpty && !bigText.hasSuffix(" ") && !newText.hasPrefix(" ") {
                bigText += " "
                charToCue.append(idx)
                charToRawPos.append(rawPos(forNormPos: overlap, cue: cue, normText: normText))
            }

            // Per-char mapping for each char we just appended.
            let rawLen = max(1, cue.text.count)
            let normLen = max(1, normText.count)
            for offset in 0..<newText.count {
                charToCue.append(idx)
                // Approximate the cue's raw-text position for the char at
                // (overlap + offset) in its normalized text.
                let normPos = overlap + offset
                let rPos = Int(Double(normPos) / Double(normLen) * Double(rawLen))
                charToRawPos.append(min(rPos, rawLen - 1))
            }
            bigText += newText
        }

        return CaptionIndex(
            cues: cues,
            bigText: bigText,
            charToCue: charToCue,
            charToRawPos: charToRawPos
        )
    }

    private static func rawPos(forNormPos normPos: Int, cue: Cue, normText: String) -> Int {
        let rawLen = max(1, cue.text.count)
        let normLen = max(1, normText.count)
        return min(Int(Double(normPos) / Double(normLen) * Double(rawLen)), rawLen - 1)
    }

}

// MARK: - Matching

extension CaptionIndex {

    /// Find the best clip range for a query. Returns `nil` if no match.
    ///
    /// Uses `.rfind` — auto-captions often restate text as the commentator
    /// speaks, and the final/cleanest match tends to be the last occurrence.
    func findRange(query: String) -> ClipRange? {
        let cleaned = Self.stripTranscriptMarkers(query)
        let normQuery = Self.normalizeStatic(cleaned)
        guard !normQuery.isEmpty else { return nil }

        // 1. Fast path: whole query matches verbatim.
        if let r = lastRange(of: normQuery) {
            return rangeFromMatch(r)
        }

        // 2. Fallback: anchor START with progressively shorter prefixes, END
        // with progressively shorter suffixes. Auto-captions diverge from the
        // transcript-panel text in tricky ways (proper nouns, self-corrections,
        // "uh"s, rolling-caption dedup) — shorter anchors are more forgiving.
        let words = normQuery.split(separator: " ").map(String.init)
        guard words.count >= 2 else { return nil }

        // Find the longest matching prefix.
        var startMatch: Range<String.Index>? = nil
        var matchedPrefixLen = 0
        for n in stride(from: min(words.count, 12), through: 2, by: -1) {
            let prefix = words.prefix(n).joined(separator: " ")
            if let r = lastRange(of: prefix) {
                startMatch = r
                matchedPrefixLen = n
                break
            }
        }
        guard let startR = startMatch else { return nil }

        // Search for the longest matching suffix that appears AFTER the prefix.
        let searchStart = bigText.index(after: startR.lowerBound)
        let remaining = words.dropFirst(matchedPrefixLen)
        var endMatch: Range<String.Index>? = nil
        for n in stride(from: min(remaining.count, 12), through: 2, by: -1) {
            let suffix = remaining.suffix(n).joined(separator: " ")
            if let r = bigText.range(of: suffix, range: searchStart..<bigText.endIndex) {
                endMatch = r
                break
            }
        }
        if let endR = endMatch {
            return rangeFromMatch(startR.lowerBound..<endR.upperBound)
        }
        // No suffix anchor — use the prefix match alone.
        return rangeFromMatch(startR)
    }

    /// Walks the big text and returns the LAST occurrence of `needle`.
    private func lastRange(of needle: String) -> Range<String.Index>? {
        var searchRange = bigText.startIndex..<bigText.endIndex
        var last: Range<String.Index>? = nil
        while let r = bigText.range(of: needle, options: [], range: searchRange) {
            last = r
            searchRange = bigText.index(after: r.lowerBound)..<bigText.endIndex
        }
        return last
    }

    private func rangeFromMatch(_ match: Range<String.Index>) -> ClipRange? {
        let startChar = bigText.distance(from: bigText.startIndex, to: match.lowerBound)
        let endChar = bigText.distance(from: bigText.startIndex, to: match.upperBound) - 1
        guard startChar < charToCue.count, endChar < charToCue.count, endChar >= 0 else { return nil }

        let startCue = cues[charToCue[startChar]]
        let endCue = cues[charToCue[endChar]]

        let startSec = timeAt(charPos: charToRawPos[startChar], in: startCue)
        let rawEnd = charToRawPos[endChar]
        let endSec = timeAt(charPos: rawEnd, in: endCue, endOfWord: true)

        return ClipRange(start: startSec, end: endSec)
    }

    /// Look up the timestamp for a char position within a cue. Uses the cue's
    /// word anchors when available (YouTube auto-caption precision), otherwise
    /// linearly interpolates over [cue.start, cue.end].
    ///
    /// When `endOfWord` is true, returns the NEXT anchor's timestamp (so the
    /// last matched word is fully included).
    private func timeAt(charPos: Int, in cue: Cue, endOfWord: Bool = false) -> TimeInterval {
        if !cue.wordAnchors.isEmpty {
            if endOfWord {
                for (apos, ats) in cue.wordAnchors where apos > charPos {
                    return ats
                }
                return cue.end
            } else {
                var best = cue.start
                for (apos, ats) in cue.wordAnchors {
                    if apos <= charPos { best = ats } else { break }
                }
                return best
            }
        }
        let rawLen = max(1, cue.text.count)
        let frac = min(max(Double(charPos) / Double(rawLen), 0), 1)
        return cue.start + (cue.end - cue.start) * frac
    }

    /// Strip YouTube transcript-panel artifacts from a selection:
    ///   - Visible timestamps:           "5:14", "1:02:33"
    ///   - Screen-reader equivalents:    "5 minutes, 14 seconds"
    ///                                   "1 hour, 2 minutes, 33 seconds"
    /// These show up because YouTube renders both the visible timestamp AND
    /// its accessibility label, and a text selection grabs both.
    static func stripTranscriptMarkers(_ s: String) -> String {
        var out = s
        // YouTube's transcript panel selection looks like:
        //   "5:265 minutes, 26 secondsAndover still in control..."
        //   "1:02:331 hour, 2 minutes, 33 secondsRickley on the faceoff..."
        // Visible timestamp + screen-reader label glued together with no
        // spaces. The last digit of the timestamp fuses into the first digit
        // of the readout, so we must match them as one combined unit.
        let combinedRE = try! NSRegularExpression(
            pattern: #"\d{1,2}:\d{2}(?::\d{2})?(?:\s*\d+\s*(?:hours?|minutes?|seconds?),?)+"#,
            options: [.caseInsensitive]
        )
        // Also handle stray bare timestamps and bare a11y readouts in case
        // either appears alone.
        let bareTimestampRE = try! NSRegularExpression(pattern: #"\d{1,2}:\d{2}(?::\d{2})?"#)
        let bareA11yRE = try! NSRegularExpression(
            pattern: #"\d+\s*(?:hours?|minutes?|seconds?),?"#,
            options: [.caseInsensitive]
        )
        for re in [combinedRE, bareTimestampRE, bareA11yRE] {
            let range = NSRange(out.startIndex..., in: out)
            out = re.stringByReplacingMatches(in: out, range: range, withTemplate: " ")
        }
        return out
    }

    // Single source of truth for normalization (used in build + findRange).
    fileprivate static func normalizeStatic(_ s: String) -> String {
        let lower = s.lowercased()
        var out = ""
        out.reserveCapacity(lower.count)
        var lastSpace = false
        for c in lower.unicodeScalars {
            if c.properties.isAlphabetic || (c.value >= 0x30 && c.value <= 0x39) {
                out.unicodeScalars.append(c)
                lastSpace = false
            } else if CharacterSet.whitespaces.contains(c) || c == "-" || c == "_" {
                if !lastSpace && !out.isEmpty {
                    out.append(" ")
                    lastSpace = true
                }
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
