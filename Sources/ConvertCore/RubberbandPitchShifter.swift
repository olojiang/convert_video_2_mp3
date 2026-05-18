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
    public let stemSelection: AudioStemSelection
    public let processingMode: AudioProcessingMode

    public init(
        sourceURL: URL,
        outputURL: URL,
        direction: PitchShiftDirection,
        semitones: Int,
        stemSelection: AudioStemSelection = .original,
        processingMode: AudioProcessingMode = .pitchShift
    ) {
        self.sourceURL = sourceURL
        self.outputURL = outputURL
        self.direction = direction
        self.semitones = semitones
        self.stemSelection = stemSelection
        self.processingMode = processingMode
    }

    public var pitchValue: Int {
        direction.sign * semitones
    }
}

public enum AudioProcessingMode: String, Codable, Equatable, CaseIterable {
    case exportOnly
    case pitchShift
}

public enum AudioStemSelection: String, Codable, Equatable, CaseIterable {
    case original
    case vocals
    case accompaniment

    public var outputSuffix: String {
        switch self {
        case .original: return "original"
        case .vocals: return "vocals"
        case .accompaniment: return "background"
        }
    }

    fileprivate var demucsOutputFileName: String? {
        switch self {
        case .original: return nil
        case .vocals: return "vocals.wav"
        case .accompaniment: return "no_vocals.wav"
        }
    }
}

public enum PitchShiftError: Error, Equatable, LocalizedError {
    case cancelled
    case ffmpegNotFound
    case rubberbandNotFound
    case demucsNotFound
    case invalidSource
    case invalidSemitoneCount
    case separatedStemMissing(String)
    case commandFailed(String, Int32, String)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Pitch shift was cancelled."
        case .ffmpegNotFound:
            return "ffmpeg was not found. Install it with Homebrew: brew install ffmpeg."
        case .rubberbandNotFound:
            return "rubberband was not found. Install it with Homebrew: brew install rubberband."
        case .demucsNotFound:
            return "Demucs was not found. Install it with pipx install demucs, or python3 -m pip install -U demucs."
        case .invalidSource:
            return "请选择一个已存在的 MP3 文件。"
        case .invalidSemitoneCount:
            return "半音数量必须大于 0。"
        case let .separatedStemMissing(path):
            return "Demucs 分离完成后没有找到目标音轨：\(path)"
        case let .commandFailed(tool, code, output):
            return "\(tool) failed with exit code \(code): \(output)"
        }
    }
}

public final class RubberbandPitchShifter {
    private let ffmpegURL: URL?
    private let rubberbandURL: URL?
    private let demucsURL: URL?
    private let runner: ProcessRunning

    public init(
        ffmpegURL: URL? = FFmpegLocator.find(),
        rubberbandURL: URL? = RubberbandLocator.find(),
        demucsURL: URL? = DemucsLocator.find(),
        runner: ProcessRunning = ProcessCommandRunner()
    ) {
        self.ffmpegURL = ffmpegURL
        self.rubberbandURL = rubberbandURL
        self.demucsURL = demucsURL
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
        guard request.processingMode == .exportOnly || request.semitones > 0 else {
            throw PitchShiftError.invalidSemitoneCount
        }
        guard let ffmpegURL else {
            throw PitchShiftError.ffmpegNotFound
        }
        if request.processingMode == .pitchShift, rubberbandURL == nil {
            throw PitchShiftError.rubberbandNotFound
        }
        if request.stemSelection != .original, demucsURL == nil {
            throw PitchShiftError.demucsNotFound
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

        let pitchSourceURL: URL
        let totalSteps: Double
        switch (request.stemSelection, request.processingMode) {
        case (.original, .exportOnly):
            totalSteps = 1
        case (_, .exportOnly):
            totalSteps = 2
        case (.original, .pitchShift):
            totalSteps = 3
        case (_, .pitchShift):
            totalSteps = 4
        }
        var completedSteps = 0.0

        if request.stemSelection == .original {
            pitchSourceURL = request.sourceURL
        } else {
            guard let demucsURL else {
                throw PitchShiftError.demucsNotFound
            }
            pitchSourceURL = try await separateStem(
                source: request.sourceURL,
                stemSelection: request.stemSelection,
                outputDirectory: workDirectory.appendingPathComponent("separated", isDirectory: true),
                demucsURL: demucsURL,
                cancellation: cancellation
            )
            completedSteps += 1
            progress(completedSteps / totalSteps)
        }

        if request.processingMode == .exportOnly {
            try await run(
                tool: "ffmpeg",
                executableURL: ffmpegURL,
                arguments: [
                    "-hide_banner",
                    "-nostats",
                    "-y",
                    "-i",
                    pitchSourceURL.path,
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
            return
        }

        guard let rubberbandURL else {
            throw PitchShiftError.rubberbandNotFound
        }

        try await run(
            tool: "ffmpeg",
            executableURL: ffmpegURL,
            arguments: ["-hide_banner", "-nostats", "-y", "-i", pitchSourceURL.path, inputWAV.path],
            cancellation: cancellation
        )
        completedSteps += 1
        progress(completedSteps / totalSteps)

        try await run(
            tool: "rubberband",
            executableURL: rubberbandURL,
            arguments: ["-p", "\(request.pitchValue)", inputWAV.path, outputWAV.path],
            cancellation: cancellation
        )
        completedSteps += 1
        progress(completedSteps / totalSteps)

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

    private func separateStem(
        source: URL,
        stemSelection: AudioStemSelection,
        outputDirectory: URL,
        demucsURL: URL,
        cancellation: CancellationChecking
    ) async throws -> URL {
        guard let outputFileName = stemSelection.demucsOutputFileName else {
            return source
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try await run(
            tool: "demucs",
            executableURL: demucsURL,
            arguments: [
                "--two-stems",
                "vocals",
                "--name",
                "htdemucs",
                "--out",
                outputDirectory.path,
                source.path
            ],
            cancellation: cancellation
        )

        let separatedURL = outputDirectory
            .appendingPathComponent("htdemucs", isDirectory: true)
            .appendingPathComponent(source.deletingPathExtension().lastPathComponent, isDirectory: true)
            .appendingPathComponent(outputFileName)

        guard FileManager.default.fileExists(atPath: separatedURL.path) else {
            throw PitchShiftError.separatedStemMissing(separatedURL.path)
        }
        return separatedURL
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

public enum DemucsLocator {
    public static func find() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/demucs",
            "/usr/local/bin/demucs",
            "/usr/bin/demucs",
            "\(NSHomeDirectory())/.local/bin/demucs"
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
