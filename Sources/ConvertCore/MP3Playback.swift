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

public enum MP3TrackSortColumn: String, Codable, Equatable, CaseIterable {
    case fileName
    case fileSize
}

public struct MP3TrackSortOption: Codable, Equatable {
    public var column: MP3TrackSortColumn
    public var direction: SortDirection

    public init(column: MP3TrackSortColumn = .fileName, direction: SortDirection = .ascending) {
        self.column = column
        self.direction = direction
    }
}

public struct MP3TrackSorter {
    private let fileSizeReader: FileSizeReader

    public init(fileSizeReader: FileSizeReader = FileSizeReader()) {
        self.fileSizeReader = fileSizeReader
    }

    public func sorted(_ tracks: [MP3Track], by option: MP3TrackSortOption) -> [MP3Track] {
        tracks.sorted { lhs, rhs in
            compare(lhs, rhs, by: option) == .orderedAscending
        }
    }

    private func compare(
        _ lhs: MP3Track,
        _ rhs: MP3Track,
        by option: MP3TrackSortOption
    ) -> ComparisonResult {
        let result: ComparisonResult
        switch option.column {
        case .fileName:
            result = compareFileNames(lhs, rhs)
        case .fileSize:
            result = compareSizes(
                fileSizeReader.sizeOfFile(at: lhs.url),
                fileSizeReader.sizeOfFile(at: rhs.url),
                lhs,
                rhs,
                direction: option.direction
            )
        }

        guard option.column == .fileName, option.direction == .descending else { return result }
        switch result {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }

    private func compareSizes(
        _ lhsSize: Int64?,
        _ rhsSize: Int64?,
        _ lhs: MP3Track,
        _ rhs: MP3Track,
        direction: SortDirection
    ) -> ComparisonResult {
        switch (lhsSize, rhsSize) {
        case let (lhsSize?, rhsSize?):
            if lhsSize < rhsSize {
                return direction == .ascending ? .orderedAscending : .orderedDescending
            }
            if lhsSize > rhsSize {
                return direction == .ascending ? .orderedDescending : .orderedAscending
            }
            return compareFileNames(lhs, rhs)
        case (nil, nil):
            return compareFileNames(lhs, rhs)
        case (nil, _?):
            return .orderedDescending
        case (_?, nil):
            return .orderedAscending
        }
    }

    private func compareFileNames(_ lhs: MP3Track, _ rhs: MP3Track) -> ComparisonResult {
        let nameResult = lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent)
        guard nameResult == .orderedSame else { return nameResult }
        return lhs.url.path.localizedStandardCompare(rhs.url.path)
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
