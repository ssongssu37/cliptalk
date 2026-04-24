import Foundation

/// A single study bit: the MP3 plus its broadcast transcript and (optional)
/// plain-English rewrite. Backed by three files sharing one stem:
///   {stem}.mp3          audio
///   {stem}.txt          broadcast transcript
///   {stem}.clean.txt    plain English (optional)
struct Bit: Identifiable, Hashable {
    let id: String            // the file stem, unique per bit
    let audioURL: URL
    let transcriptURL: URL?
    let cleanURL: URL?

    var transcript: String {
        guard let url = transcriptURL else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var cleanEnglish: String {
        guard let url = cleanURL else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var hasTranscript: Bool { transcriptURL != nil }
    var hasClean: Bool { cleanURL != nil }

    /// "Maple_Grove_vs_Andover__00-17-25_to_00-17-28" → friendly label.
    var prettyTitle: String {
        let parts = id.components(separatedBy: "__")
        let main = parts.first?.replacingOccurrences(of: "_", with: " ") ?? id
        if parts.count > 1 {
            let range = parts[1]
                .replacingOccurrences(of: "_to_", with: " – ")
                .replacingOccurrences(of: "-", with: ":")
                .replacingOccurrences(of: "_", with: " ")
            return "\(main) · \(range)"
        }
        return main
    }
}
