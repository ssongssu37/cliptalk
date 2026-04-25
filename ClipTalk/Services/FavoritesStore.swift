import Foundation

/// Tracks which bits the user has favorited for the Study Book.
/// Stored as a flat JSON array of bit IDs at:
///   ~/Library/Application Support/ClipTalk/favorites.json
///
/// A bit ID is the file stem (e.g. "Hockey_Game__00-09-46_to_00-09-56").
/// Favoriting is separate from the filesystem bit itself — removing from the
/// Study Book only un-favorites; the MP3 stays in bits/.
enum FavoritesStore {

    private static var fileURL: URL {
        LibraryPaths.supportDir.appendingPathComponent("favorites.json")
    }

    /// Full set of currently favorited bit IDs. Safe to call from any thread.
    static func load() -> Set<String> {
        guard let data = try? Data(contentsOf: fileURL),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(ids)
    }

    static func save(_ ids: Set<String>) {
        let sorted = ids.sorted()
        if let data = try? JSONEncoder().encode(sorted) {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }

    static func isFavorited(_ id: String) -> Bool {
        load().contains(id)
    }

    static func add(_ id: String) {
        var ids = load()
        ids.insert(id)
        save(ids)
    }

    static func remove(_ id: String) {
        var ids = load()
        ids.remove(id)
        save(ids)
    }

    @discardableResult
    static func toggle(_ id: String) -> Bool {
        var ids = load()
        let nowFavorited: Bool
        if ids.contains(id) {
            ids.remove(id)
            nowFavorited = false
        } else {
            ids.insert(id)
            nowFavorited = true
        }
        save(ids)
        return nowFavorited
    }
}
