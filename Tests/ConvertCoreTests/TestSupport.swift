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
    private let queue = DispatchQueue(label: "tests.memory-logger")
    private var storedEvents: [(level: LogLevel, event: String, details: [String: String])] = []

    var events: [(level: LogLevel, event: String, details: [String: String])] {
        queue.sync { storedEvents }
    }

    func log(_ level: LogLevel, event: String, details: [String: String]) {
        queue.sync {
            storedEvents.append((level, event, details))
        }
    }
}

final class FakeAudioExtractor: AudioExtracting {
    private let queue = DispatchQueue(label: "tests.fake-audio-extractor")
    private let delayNanoseconds: UInt64
    private let progressFractions: [Double]
    private var active = 0
    private var storedMaxActive = 0
    private var storedStartedCount = 0

    var maxActive: Int {
        queue.sync { storedMaxActive }
    }

    var startedCount: Int {
        queue.sync { storedStartedCount }
    }

    init(delayNanoseconds: UInt64, progressFractions: [Double] = []) {
        self.delayNanoseconds = delayNanoseconds
        self.progressFractions = progressFractions
    }

    func extractMP3(
        source: URL,
        tempOutput: URL,
        finalOutput: URL,
        cancellation: CancellationChecking,
        progress: @escaping (Double) -> Void
    ) async throws {
        queue.sync {
            active += 1
            storedStartedCount += 1
            storedMaxActive = max(storedMaxActive, active)
        }

        defer {
            queue.sync {
                active -= 1
            }
        }

        for fraction in progressFractions {
            progress(fraction)
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

final class ProgressRecorder {
    private let queue = DispatchQueue(label: "tests.progress-recorder")
    private var values: [Double] = []

    var progressValues: [Double] {
        queue.sync { values }
    }

    func record(_ task: ConversionTask) {
        queue.sync {
            values.append(task.progress)
        }
    }
}
