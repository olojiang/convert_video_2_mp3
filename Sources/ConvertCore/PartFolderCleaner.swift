import Foundation

public struct PartFolderCandidate: Codable, Equatable, Hashable, Identifiable {
    public var id: String { folderURL.path }
    public let folderURL: URL
    public let partFiles: [URL]

    public init(folderURL: URL, partFiles: [URL]) {
        self.folderURL = folderURL
        self.partFiles = partFiles
    }
}

public struct PartFolderCleaner {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan(root: URL) throws -> [PartFolderCandidate] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var partFilesByFolder: [URL: [URL]] = [:]
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            guard fileURL.lastPathComponent.lowercased().hasSuffix(".mp4.part") else { continue }

            partFilesByFolder[fileURL.deletingLastPathComponent(), default: []].append(fileURL)
        }

        return partFilesByFolder
            .map { folderURL, partFiles in
                PartFolderCandidate(
                    folderURL: folderURL,
                    partFiles: partFiles.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
                )
            }
            .sorted { $0.folderURL.path.localizedStandardCompare($1.folderURL.path) == .orderedAscending }
    }

    public func deleteFolders(_ candidates: [PartFolderCandidate]) throws -> Int {
        var deleted = 0
        for candidate in candidates {
            guard fileManager.fileExists(atPath: candidate.folderURL.path) else { continue }
            try fileManager.removeItem(at: candidate.folderURL)
            deleted += 1
        }
        return deleted
    }
}
