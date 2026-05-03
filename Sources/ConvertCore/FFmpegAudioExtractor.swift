import Foundation

public final class FFmpegAudioExtractor: AudioExtracting {
    private let executableURL: URL?
    private let processLock = NSLock()
    private var activeProcesses: [Process] = []

    public init(executableURL: URL? = FFmpegLocator.find()) {
        self.executableURL = executableURL
    }

    public func extractMP3(
        source: URL,
        tempOutput: URL,
        finalOutput: URL,
        cancellation: CancellationChecking
    ) async throws {
        guard let executableURL else {
            throw ConversionError.ffmpegNotFound
        }

        try FileManager.default.createDirectory(
            at: finalOutput.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "-hide_banner",
            "-y",
            "-i", source.path,
            "-vn",
            "-codec:a", "libmp3lame",
            "-q:a", "2",
            tempOutput.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        register(process)
        defer { unregister(process) }

        try process.run()

        while process.isRunning {
            if cancellation.isCancellationRequested {
                process.terminate()
                process.waitUntilExit()
                throw ConversionError.cancelled
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: tempOutput)
            throw ConversionError.ffmpegFailed(process.terminationStatus, output)
        }

        if FileManager.default.fileExists(atPath: finalOutput.path) {
            try FileManager.default.removeItem(at: finalOutput)
        }
        try FileManager.default.moveItem(at: tempOutput, to: finalOutput)
    }

    public func terminateAll() {
        processLock.lock()
        let processes = activeProcesses
        processLock.unlock()
        processes.forEach { process in
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private func register(_ process: Process) {
        processLock.lock()
        activeProcesses.append(process)
        processLock.unlock()
    }

    private func unregister(_ process: Process) {
        processLock.lock()
        activeProcesses.removeAll { $0 === process }
        processLock.unlock()
    }
}

public enum FFmpegLocator {
    public static func find() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
