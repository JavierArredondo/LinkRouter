import Foundation

actor ConfigurationStore {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LinkRouter", isDirectory: true)
        self.fileURL = support.appendingPathComponent("configuration.json")
    }

    func load() -> AppConfiguration {
        guard fileManager.fileExists(atPath: fileURL.path) else { return AppConfiguration() }
        do { return try JSONDecoder().decode(AppConfiguration.self, from: Data(contentsOf: fileURL)) }
        catch {
            let backup = fileURL.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? fileManager.moveItem(at: fileURL, to: backup)
            return AppConfiguration()
        }
    }

    func save(_ configuration: AppConfiguration) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.pretty.encode(configuration)
        try data.write(to: fileURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder }
}
