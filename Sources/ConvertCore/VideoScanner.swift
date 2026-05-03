import Foundation

public struct VideoScanner {
    public static let supportedExtensions: Set<String> = [
        "3gp", "avi", "flv", "m4v", "mkv", "mov", "mp4", "mpeg",
        "mpg", "mts", "ts", "webm", "wmv"
    ]

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan(root: URL) throws -> [VideoFile] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var videos: [VideoFile] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }

            let ext = fileURL.pathExtension.lowercased()
            guard Self.supportedExtensions.contains(ext) else { continue }

            videos.append(VideoFile(
                sourceURL: fileURL,
                outputURL: fileURL.deletingPathExtension().appendingPathExtension("mp3")
            ))
        }

        return videos.sorted { $0.sourceURL.path.localizedStandardCompare($1.sourceURL.path) == .orderedAscending }
    }
}
