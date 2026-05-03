import Foundation

public struct MP3Track: Codable, Equatable, Hashable, Identifiable {
    public var id: String { url.path }
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}

public struct MP3Scanner {
    public static let supportedExtensions: Set<String> = ["mp3"]

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan(root: URL) throws -> [MP3Track] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var tracks: [MP3Track] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }

            let ext = fileURL.pathExtension.lowercased()
            guard Self.supportedExtensions.contains(ext) else { continue }

            tracks.append(MP3Track(url: fileURL))
        }

        return tracks.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }
}

public struct MP3PlaybackPosition: Codable, Equatable {
    public let trackID: String
    public let time: TimeInterval

    public init(trackID: String, time: TimeInterval) {
        self.trackID = trackID
        self.time = max(0, time)
    }
}

public final class MP3PlaybackStateStore {
    private let stateURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(stateURL: URL, fileManager: FileManager = .default) {
        self.stateURL = stateURL
        self.fileManager = fileManager
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load(for tracks: [MP3Track]) throws -> MP3PlaybackPosition? {
        guard fileManager.fileExists(atPath: stateURL.path) else { return nil }
        let data = try Data(contentsOf: stateURL)
        let position = try decoder.decode(MP3PlaybackPosition.self, from: data)
        guard tracks.contains(where: { $0.id == position.trackID }) else { return nil }
        return position
    }

    public func save(_ position: MP3PlaybackPosition?) throws {
        try fileManager.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let position else {
            if fileManager.fileExists(atPath: stateURL.path) {
                try fileManager.removeItem(at: stateURL)
            }
            return
        }

        let data = try encoder.encode(position)
        try data.write(to: stateURL, options: [.atomic])
    }
}
