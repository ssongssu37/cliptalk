import Foundation

/// A single row in the Clip tab's history list.
struct HistoryEntry: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        case mp3, transcript, both, clip, warm

        var label: String {
            switch self {
            case .mp3: return "MP3"
            case .transcript: return "Transcript"
            case .both: return "Both"
            case .clip: return "Clip"
            case .warm: return "Warm"
            }
        }
    }

    enum Status: String, Codable {
        case done, error
    }

    var id: UUID
    let timestamp: Date
    let kind: Kind
    let status: Status
    let message: String
    let url: String
    /// For clip-by-text entries: the transcript text the user pasted.
    let query: String?
    /// Absolute paths of files produced on disk.
    let producedPaths: [String]
    /// True once the user has imported the produced .mp3 into bits/.
    var sentToBits: Bool
}

/// Loads and persists history.json. All file IO lives here.
enum HistoryStore {

    private static var fileURL: URL {
        LibraryPaths.supportDir.appendingPathComponent("history.json")
    }

    static func load() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    static func save(_ entries: [HistoryEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
