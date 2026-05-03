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
        cancellation: CancellationChecking,
        progress: @escaping (Double) -> Void
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
            "-nostats",
            "-progress", "pipe:1",
            "-y",
            "-i", source.path,
            "-vn",
            "-codec:a", "libmp3lame",
            "-q:a", "2",
            "-f", "mp3",
            tempOutput.path
        ]

        let progressPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = progressPipe
        process.standardError = errorPipe

        let duration = FFprobeDurationReader().durationSeconds(for: source)
        let parser = FFmpegProgressParser(durationSeconds: duration)
        progressPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for fraction in parser.parse(text) {
                progress(fraction)
            }
        }

        register(process)
        defer {
            progressPipe.fileHandleForReading.readabilityHandler = nil
            unregister(process)
        }

        try process.run()

        while process.isRunning {
            if cancellation.isCancellationRequested {
                process.terminate()
                process.waitUntilExit()
                throw ConversionError.cancelled
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: tempOutput)
            throw ConversionError.ffmpegFailed(process.terminationStatus, output)
        }

        if FileManager.default.fileExists(atPath: finalOutput.path) {
            try FileManager.default.removeItem(at: finalOutput)
        }
        try FileManager.default.moveItem(at: tempOutput, to: finalOutput)
        progress(1)
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

public final class FFmpegProgressParser {
    private let durationSeconds: Double?

    public init(durationSeconds: Double?) {
        self.durationSeconds = durationSeconds
    }

    public func parse(_ text: String) -> [Double] {
        var fractions: [Double] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }

            if parts[0] == "out_time_ms",
               let durationSeconds,
               durationSeconds > 0,
               let microseconds = Double(parts[1]) {
                let seconds = microseconds / 1_000_000
                fractions.append(min(max(seconds / durationSeconds, 0), 0.99))
            }

            if parts[0] == "progress", parts[1] == "end" {
                fractions.append(1)
            }
        }
        return fractions
    }
}

public struct FFprobeDurationReader {
    private let executableURL: URL?

    public init(executableURL: URL? = FFmpegLocator.findFFprobe()) {
        self.executableURL = executableURL
    }

    public func durationSeconds(for source: URL) -> Double? {
        guard let executableURL else { return nil }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            source.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.flatMap(Double.init)
        } catch {
            return nil
        }
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

    public static func findFFprobe() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe",
            "/usr/bin/ffprobe"
        ]
        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
