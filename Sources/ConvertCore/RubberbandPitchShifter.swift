import Foundation

public enum PitchShiftDirection: String, Codable, Equatable, CaseIterable {
    case up
    case down

    public var sign: Int {
        switch self {
        case .up: return 1
        case .down: return -1
        }
    }
}

public struct PitchShiftRequest: Equatable {
    public let sourceURL: URL
    public let outputURL: URL
    public let direction: PitchShiftDirection
    public let semitones: Int

    public init(sourceURL: URL, outputURL: URL, direction: PitchShiftDirection, semitones: Int) {
        self.sourceURL = sourceURL
        self.outputURL = outputURL
        self.direction = direction
        self.semitones = semitones
    }

    public var pitchValue: Int {
        direction.sign * semitones
    }
}

public enum PitchShiftError: Error, Equatable, LocalizedError {
    case cancelled
    case ffmpegNotFound
    case rubberbandNotFound
    case invalidSource
    case invalidSemitoneCount
    case commandFailed(String, Int32, String)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Pitch shift was cancelled."
        case .ffmpegNotFound:
            return "ffmpeg was not found. Install it with Homebrew: brew install ffmpeg."
        case .rubberbandNotFound:
            return "rubberband was not found. Install it with Homebrew: brew install rubberband."
        case .invalidSource:
            return "请选择一个已存在的 MP3 文件。"
        case .invalidSemitoneCount:
            return "半音数量必须大于 0。"
        case let .commandFailed(tool, code, output):
            return "\(tool) failed with exit code \(code): \(output)"
        }
    }
}

public final class RubberbandPitchShifter {
    private let ffmpegURL: URL?
    private let rubberbandURL: URL?
    private let runner: ProcessRunning

    public init(
        ffmpegURL: URL? = FFmpegLocator.find(),
        rubberbandURL: URL? = RubberbandLocator.find(),
        runner: ProcessRunning = ProcessCommandRunner()
    ) {
        self.ffmpegURL = ffmpegURL
        self.rubberbandURL = rubberbandURL
        self.runner = runner
    }

    public func shiftPitch(
        request: PitchShiftRequest,
        cancellation: CancellationChecking,
        progress: @escaping (Double) -> Void
    ) async throws {
        guard FileManager.default.fileExists(atPath: request.sourceURL.path),
              request.sourceURL.pathExtension.lowercased() == "mp3" else {
            throw PitchShiftError.invalidSource
        }
        guard request.semitones > 0 else {
            throw PitchShiftError.invalidSemitoneCount
        }
        guard let ffmpegURL else {
            throw PitchShiftError.ffmpegNotFound
        }
        guard let rubberbandURL else {
            throw PitchShiftError.rubberbandNotFound
        }

        try FileManager.default.createDirectory(
            at: request.outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConvertVideo2MP3-Pitch-\(UUID().uuidString)", isDirectory: true)
        let inputWAV = workDirectory.appendingPathComponent("input.wav")
        let outputWAV = workDirectory.appendingPathComponent("output.wav")
        let tempMP3 = request.outputURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(request.outputURL.lastPathComponent).part")

        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: workDirectory)
            try? FileManager.default.removeItem(at: tempMP3)
        }

        if cancellation.isCancellationRequested {
            throw PitchShiftError.cancelled
        }

        try await run(
            tool: "ffmpeg",
            executableURL: ffmpegURL,
            arguments: ["-hide_banner", "-nostats", "-y", "-i", request.sourceURL.path, inputWAV.path],
            cancellation: cancellation
        )
        progress(1.0 / 3.0)

        try await run(
            tool: "rubberband",
            executableURL: rubberbandURL,
            arguments: ["-p", "\(request.pitchValue)", inputWAV.path, outputWAV.path],
            cancellation: cancellation
        )
        progress(2.0 / 3.0)

        try await run(
            tool: "ffmpeg",
            executableURL: ffmpegURL,
            arguments: [
                "-hide_banner",
                "-nostats",
                "-y",
                "-i",
                outputWAV.path,
                "-codec:a",
                "libmp3lame",
                "-q:a",
                "2",
                "-f",
                "mp3",
                tempMP3.path
            ],
            cancellation: cancellation
        )

        if FileManager.default.fileExists(atPath: request.outputURL.path) {
            try FileManager.default.removeItem(at: request.outputURL)
        }
        try FileManager.default.moveItem(at: tempMP3, to: request.outputURL)
        progress(1)
    }

    private func run(
        tool: String,
        executableURL: URL,
        arguments: [String],
        cancellation: CancellationChecking
    ) async throws {
        if cancellation.isCancellationRequested {
            throw PitchShiftError.cancelled
        }

        let result = try await runner.run(
            executableURL: executableURL,
            arguments: arguments,
            cancellation: cancellation
        )
        guard result.exitCode == 0 else {
            throw PitchShiftError.commandFailed(tool, result.exitCode, result.output)
        }
    }
}

public enum RubberbandLocator {
    public static func find() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/rubberband",
            "/usr/local/bin/rubberband",
            "/usr/bin/rubberband"
        ]
        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

public struct ProcessResult: Equatable {
    public let exitCode: Int32
    public let output: String

    public init(exitCode: Int32, output: String) {
        self.exitCode = exitCode
        self.output = output
    }
}

public protocol ProcessRunning: AnyObject {
    func run(
        executableURL: URL,
        arguments: [String],
        cancellation: CancellationChecking
    ) async throws -> ProcessResult
}

public final class ProcessCommandRunner: ProcessRunning {
    private let lock = NSLock()
    private var activeProcesses: [Process] = []

    public init() {}

    public func run(
        executableURL: URL,
        arguments: [String],
        cancellation: CancellationChecking
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        register(process)
        defer {
            unregister(process)
        }

        try process.run()
        while process.isRunning {
            if cancellation.isCancellationRequested {
                process.terminate()
                process.waitUntilExit()
                throw PitchShiftError.cancelled
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return ProcessResult(exitCode: process.terminationStatus, output: output)
    }

    public func terminateAll() {
        lock.lock()
        let processes = activeProcesses
        lock.unlock()
        processes.forEach { process in
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private func register(_ process: Process) {
        lock.lock()
        activeProcesses.append(process)
        lock.unlock()
    }

    private func unregister(_ process: Process) {
        lock.lock()
        activeProcesses.removeAll { $0 === process }
        lock.unlock()
    }
}
