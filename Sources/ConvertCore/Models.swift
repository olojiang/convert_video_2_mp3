import Foundation

public struct VideoFile: Codable, Equatable, Hashable, Identifiable {
    public var id: String { sourceURL.path }
    public let sourceURL: URL
    public let outputURL: URL

    public init(sourceURL: URL, outputURL: URL) {
        self.sourceURL = sourceURL
        self.outputURL = outputURL
    }
}

public enum ConversionStatus: String, Codable, Equatable, CaseIterable {
    case pending
    case converting
    case succeeded
    case failed
    case cancelled
}

public struct ConversionTask: Codable, Equatable, Identifiable {
    public var id: String { video.id }
    public let video: VideoFile
    public var status: ConversionStatus
    public var errorMessage: String?
    public var updatedAt: Date

    public var sourceURL: URL { video.sourceURL }
    public var outputURL: URL { video.outputURL }

    public init(
        video: VideoFile,
        status: ConversionStatus = .pending,
        errorMessage: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.video = video
        self.status = status
        self.errorMessage = errorMessage
        self.updatedAt = updatedAt
    }
}

public enum ConversionError: Error, Equatable, LocalizedError {
    case cancelled
    case ffmpegNotFound
    case ffmpegFailed(Int32, String)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Conversion was cancelled."
        case .ffmpegNotFound:
            return "ffmpeg was not found. Install it with Homebrew: brew install ffmpeg."
        case let .ffmpegFailed(code, output):
            return "ffmpeg failed with exit code \(code): \(output)"
        }
    }
}
