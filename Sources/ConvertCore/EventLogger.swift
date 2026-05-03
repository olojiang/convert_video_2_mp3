import Foundation

public enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

public protocol EventLogger: AnyObject {
    func log(_ level: LogLevel, event: String, details: [String: String])
}

public final class FileEventLogger: EventLogger {
    public let logURL: URL
    private let queue = DispatchQueue(label: "convert-video-2-mp3.file-logger")
    private let formatter: ISO8601DateFormatter

    public init(logURL: URL) throws {
        self.logURL = logURL
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
    }

    public func log(_ level: LogLevel, event: String, details: [String: String] = [:]) {
        let timestamp = formatter.string(from: Date())
        let detailText = details
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(sanitize($0.value))" }
            .joined(separator: " ")
        let line = "\(timestamp) level=\(level.rawValue) event=\(event) \(detailText)\n"

        queue.sync {
            guard let data = line.data(using: .utf8),
                  let handle = try? FileHandle(forWritingTo: self.logURL) else {
                return
            }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    private func sanitize(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: "\\n")
    }
}

public final class ConsoleEventLogger: EventLogger {
    public init() {}

    public func log(_ level: LogLevel, event: String, details: [String: String]) {
        let detailText = details.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        print("level=\(level.rawValue) event=\(event) \(detailText)")
    }
}
