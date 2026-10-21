// Small JSON documents on disk: the offline copy of the user's data and the
// queue of changes not yet uploaded. Files instead of UserDefaults because
// the history keeps growing.

import Foundation

final class FileLocalStore {
    private let root: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("data", isDirectory: true)
    }()

    private func file(_ name: String) -> URL { root.appendingPathComponent(name) }

    func read(_ name: String) -> String? {
        try? String(contentsOf: file(name), encoding: .utf8)
    }

    func write(_ name: String, _ data: String) {
        let url = file(name)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Atomic: written aside and renamed, so a crash mid-write never
        // leaves half a file.
        try? data.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Deletes every document under `prefix`.
    func deleteAll(_ prefix: String) {
        try? FileManager.default.removeItem(at: file(prefix))
    }
}
