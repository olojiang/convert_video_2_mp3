import Foundation

public final class TaskStateStore {
    private let stateURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(stateURL: URL, fileManager: FileManager = .default) {
        self.stateURL = stateURL
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load(for videos: [VideoFile]) throws -> [ConversionTask] {
        let previous = try loadRaw()
        let previousBySource = Dictionary(uniqueKeysWithValues: previous.map { ($0.sourceURL.path, $0) })

        return videos.map { video in
            if fileManager.fileExists(atPath: video.outputURL.path) {
                return ConversionTask(video: video, status: .succeeded, progress: 1)
            }

            guard var task = previousBySource[video.sourceURL.path] else {
                return ConversionTask(video: video)
            }

            if task.status == .converting || task.status == .cancelled || task.status == .failed {
                task.status = .pending
                task.progress = 0
                task.errorMessage = nil
                task.updatedAt = Date()
            }
            return task
        }
    }

    public func save(_ tasks: [ConversionTask]) throws {
        try fileManager.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(tasks)
        try data.write(to: stateURL, options: [.atomic])
    }

    private func loadRaw() throws -> [ConversionTask] {
        guard fileManager.fileExists(atPath: stateURL.path) else { return [] }
        let data = try Data(contentsOf: stateURL)
        return try decoder.decode([ConversionTask].self, from: data)
    }
}

public struct RootHistoryStore {
    private let key: String
    private let defaults: UserDefaults

    public init(key: String = "recentRootFolders", defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    public func load() -> [URL] {
        defaults.stringArray(forKey: key)?.map(URL.init(fileURLWithPath:)) ?? []
    }

    public func remember(_ url: URL) {
        var paths = load().map(\.path)
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        defaults.set(Array(paths.prefix(12)), forKey: key)
    }
}
