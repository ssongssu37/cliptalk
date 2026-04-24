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
        let normQuery = Self.normalizeStatic(query)
        guard !normQuery.isEmpty else { return nil }

        // Swift has no rfind; walk ranges manually.
        var searchRange = bigText.startIndex..<bigText.endIndex
        var lastMatch: Range<String.Index>? = nil
        while let r = bigText.range(of: normQuery, options: [], range: searchRange) {
            lastMatch = r
            searchRange = bigText.index(after: r.lowerBound)..<bigText.endIndex
        }
        guard let match = lastMatch else { return nil }

        let startChar = bigText.distance(from: bigText.startIndex, to: match.lowerBound)
        let endChar = bigText.distance(from: bigText.startIndex, to: match.upperBound) - 1
        guard startChar < charToCue.count, endChar < charToCue.count else { return nil }

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
