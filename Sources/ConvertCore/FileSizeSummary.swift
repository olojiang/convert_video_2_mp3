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

public enum ConversionTaskSortColumn: String, Codable, Equatable, CaseIterable {
    case fileName
    case videoSize
    case mp3Size
}

public enum SortDirection: String, Codable, Equatable, CaseIterable {
    case ascending
    case descending
}

public struct ConversionTaskSortOption: Codable, Equatable {
    public var column: ConversionTaskSortColumn
    public var direction: SortDirection

    public init(column: ConversionTaskSortColumn = .fileName, direction: SortDirection = .ascending) {
        self.column = column
        self.direction = direction
    }
}

public struct ConversionTaskSorter {
    private let fileSizeReader: FileSizeReader

    public init(fileSizeReader: FileSizeReader = FileSizeReader()) {
        self.fileSizeReader = fileSizeReader
    }

    public func sorted(_ tasks: [ConversionTask], by option: ConversionTaskSortOption) -> [ConversionTask] {
        tasks.sorted { lhs, rhs in
            compare(lhs, rhs, by: option) == .orderedAscending
        }
    }

    private func compare(
        _ lhs: ConversionTask,
        _ rhs: ConversionTask,
        by option: ConversionTaskSortOption
    ) -> ComparisonResult {
        let result: ComparisonResult
        switch option.column {
        case .fileName:
            result = compareFileNames(lhs, rhs)
        case .videoSize:
            result = compareSizes(
                fileSizeReader.sizeOfFile(at: lhs.sourceURL),
                fileSizeReader.sizeOfFile(at: rhs.sourceURL),
                lhs,
                rhs,
                direction: option.direction
            )
        case .mp3Size:
            result = compareSizes(
                fileSizeReader.sizeOfFile(at: lhs.outputURL),
                fileSizeReader.sizeOfFile(at: rhs.outputURL),
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
        _ lhs: ConversionTask,
        _ rhs: ConversionTask,
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

    private func compareFileNames(_ lhs: ConversionTask, _ rhs: ConversionTask) -> ComparisonResult {
        let nameResult = lhs.sourceURL.lastPathComponent.localizedStandardCompare(rhs.sourceURL.lastPathComponent)
        guard nameResult == .orderedSame else { return nameResult }
        return lhs.sourceURL.path.localizedStandardCompare(rhs.sourceURL.path)
    }
}
