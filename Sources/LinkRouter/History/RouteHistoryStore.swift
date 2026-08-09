import Foundation

actor RouteHistoryStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private var appendsSinceCompaction = 0

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LinkRouter", isDirectory: true)
        self.fileURL = support.appendingPathComponent("history.jsonl")
    }

    func record(_ entry: HistoryEntry) {
        guard let line = RouteHistoryLog.line(for: entry) else { return }
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: fileURL.path) { try Data().write(to: fileURL) }
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            return // History must never interrupt routing.
        }
        appendsSinceCompaction += 1
        if appendsSinceCompaction >= RouteHistoryLog.compactionInterval { compact() }
    }

    func entries() -> [HistoryEntry] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return RouteHistoryLog.entries(in: text)
    }

    func clear() {
        try? fileManager.removeItem(at: fileURL)
        appendsSinceCompaction = 0
    }

    private func compact() {
        appendsSinceCompaction = 0
        let all = entries()
        guard all.count > RouteHistoryLog.limit else { return }
        let text = RouteHistoryLog.trimmed(all).compactMap(RouteHistoryLog.line(for:)).joined()
        try? Data(text.utf8).write(to: fileURL, options: .atomic)
    }
}
