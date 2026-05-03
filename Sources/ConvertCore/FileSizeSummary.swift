import Foundation

public struct FileSizeSummary: Equatable {
    public let videoBytes: Int64
    public let mp3Bytes: Int64

    public init(videoBytes: Int64, mp3Bytes: Int64) {
        self.videoBytes = videoBytes
        self.mp3Bytes = mp3Bytes
    }
}

public struct FileSizeReader {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func sizeOfFile(at url: URL) -> Int64? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return size.int64Value
    }

    public func summary(for tasks: [ConversionTask]) -> FileSizeSummary {
        let videoBytes = tasks.reduce(Int64(0)) { partial, task in
            partial + (sizeOfFile(at: task.sourceURL) ?? 0)
        }
        let mp3Bytes = tasks.reduce(Int64(0)) { partial, task in
            partial + (sizeOfFile(at: task.outputURL) ?? 0)
        }
        return FileSizeSummary(videoBytes: videoBytes, mp3Bytes: mp3Bytes)
    }
}

public enum FileSizeText {
    public static func format(_ bytes: Int64?) -> String {
        guard let bytes else { return "-" }
        guard bytes > 0 else { return "0 B" }

        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(bytes) B"
        }
        if value >= 100 {
            return String(format: "%.0f %@", value, units[unitIndex])
        }
        if value >= 10 {
            return String(format: "%.1f %@", value, units[unitIndex])
        }
        return String(format: "%.2f %@", value, units[unitIndex])
    }
}
