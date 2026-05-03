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
    public var progress: Double
    public var errorMessage: String?
    public var updatedAt: Date

    public var sourceURL: URL { video.sourceURL }
    public var outputURL: URL { video.outputURL }

    public init(
        video: VideoFile,
        status: ConversionStatus = .pending,
        progress: Double = 0,
        errorMessage: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.video = video
        self.status = status
        self.progress = min(max(progress, 0), 1)
        self.errorMessage = errorMessage
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case video
        case status
        case progress
        case errorMessage
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        video = try container.decode(VideoFile.self, forKey: .video)
        status = try container.decode(ConversionStatus.self, forKey: .status)
        progress = try container.decodeIfPresent(Double.self, forKey: .progress) ?? (status == .succeeded ? 1 : 0)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

public struct ConversionOptions: Codable, Equatable {
    public var deleteSourceOnSuccess: Bool

    public init(deleteSourceOnSuccess: Bool = false) {
        self.deleteSourceOnSuccess = deleteSourceOnSuccess
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
