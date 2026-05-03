import Foundation
@testable import ConvertCore

struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConvertCoreTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func write(_ relativePath: String, contents: String) throws {
        let fileURL = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

final class MemoryLogger: EventLogger {
    private let lock = NSLock()
    private(set) var events: [(level: LogLevel, event: String, details: [String: String])] = []

    func log(_ level: LogLevel, event: String, details: [String: String]) {
        lock.lock()
        events.append((level, event, details))
        lock.unlock()
    }
}

final class FakeAudioExtractor: AudioExtracting {
    private let lock = NSLock()
    private let delayNanoseconds: UInt64
    private var active = 0
    private(set) var maxActive = 0
    private(set) var startedCount = 0

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func extractMP3(source: URL, tempOutput: URL, finalOutput: URL, cancellation: CancellationChecking) async throws {
        lock.lock()
        active += 1
        startedCount += 1
        maxActive = max(maxActive, active)
        lock.unlock()

        defer {
            lock.lock()
            active -= 1
            lock.unlock()
        }

        try await Task.sleep(nanoseconds: delayNanoseconds)
        if cancellation.isCancellationRequested {
            throw ConversionError.cancelled
        }
        try Data("mp3".utf8).write(to: tempOutput)
        if FileManager.default.fileExists(atPath: finalOutput.path) {
            try FileManager.default.removeItem(at: finalOutput)
        }
        try FileManager.default.moveItem(at: tempOutput, to: finalOutput)
    }
}
