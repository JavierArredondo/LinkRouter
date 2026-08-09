import Foundation

actor Diagnostics {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LinkRouter", isDirectory: true)
        self.fileURL = support.appendingPathComponent("diagnostics.log")
    }

    func hostCounts() -> [String: Int] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [:] }
        return DiagnosticsLog.hostCounts(in: text)
    }

    func record(host: String, outcome: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) host=\(host) outcome=\(outcome)\n"
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: fileURL.path) { try Data().write(to: fileURL) }
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch { /* Diagnostics must never interrupt routing. */ }
    }
}
