import ConvertCore
import Foundation

@main
struct ConvertVideo2MP3CLI {
    static func main() async throws {
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            printUsage()
            return
        }
        arguments.removeFirst()

        switch command {
        case "check-deps":
            checkDependencies()
        case "convert":
            try await convert(arguments)
        case "pitch":
            try await pitch(arguments)
        case "-h", "--help", "help":
            printUsage()
        default:
            throw CLIError.message("Unknown command: \(command)\n\n\(usageText)")
        }
    }

    private static func checkDependencies() {
        let report = ExternalDependencyReport.current()
        for item in report.items {
            let status = item.executableURL?.path ?? "missing"
            print("\(item.dependency.displayName): \(status)")
            if !item.isInstalled {
                print("  install: \(item.dependency.installHint)")
            }
        }
    }

    private static func convert(_ arguments: [String]) async throws {
        var parser = ArgumentParser(arguments)
        guard let rootPath = parser.takeValue() else {
            throw CLIError.message("convert requires a root directory.\n\n\(usageText)")
        }
        let concurrency = try parser.takeIntFlag("--concurrency") ?? 4
        let deleteSource = parser.takeBoolFlag("--delete-source")
        try parser.rejectUnknownFlags()

        try requireDependencies([.ffmpeg, .ffprobe])

        let rootURL = URL(fileURLWithPath: rootPath)
        let videos = try VideoScanner().scan(root: rootURL)
        let tasks = videos.map { ConversionTask(video: $0) }
        guard !tasks.isEmpty else {
            print("No supported videos found under \(rootURL.path).")
            return
        }

        print("Found \(tasks.count) video file(s).")
        let logger = CLILogger()
        let coordinator = ConversionCoordinator(
            extractor: FFmpegAudioExtractor(),
            logger: logger,
            onTaskUpdate: { task in
                print("[\(task.status.rawValue)] \(Int(task.progress * 100))% \(task.sourceURL.path)")
            }
        )
        let results = await coordinator.convert(
            tasks: tasks,
            concurrency: concurrency,
            options: ConversionOptions(deleteSourceOnSuccess: deleteSource)
        )
        let succeeded = results.filter { $0.status == .succeeded }.count
        let failed = results.filter { $0.status == .failed }.count
        let cancelled = results.filter { $0.status == .cancelled }.count
        print("Done. succeeded=\(succeeded) failed=\(failed) cancelled=\(cancelled)")
        if failed > 0 {
            throw CLIError.message("Some conversions failed.")
        }
    }

    private static func pitch(_ arguments: [String]) async throws {
        var parser = ArgumentParser(arguments)
        guard let inputPath = parser.takeValue(),
              let outputPath = parser.takeValue() else {
            throw CLIError.message("pitch requires input and output MP3 paths.\n\n\(usageText)")
        }

        let stem = try parser.takeStemFlag("--stem") ?? .original
        let mode = try parser.takeModeFlag("--mode") ?? .pitchShift
        let direction = try parser.takeDirectionFlag("--direction") ?? .up
        let semitones = try parser.takeIntFlag("--semitones") ?? 2
        try parser.rejectUnknownFlags()

        let request = PitchShiftRequest(
            sourceURL: URL(fileURLWithPath: inputPath),
            outputURL: URL(fileURLWithPath: outputPath),
            direction: direction,
            semitones: semitones,
            stemSelection: stem,
            processingMode: mode
        )
        try requireDependencies(requiredDependencies(for: request))

        try await RubberbandPitchShifter().shiftPitch(
            request: request,
            cancellation: CancellationToken(),
            progress: { fraction in
                print("progress=\(Int(fraction * 100))%")
            },
            log: { message in
                print(message)
            }
        )
    }

    private static func requiredDependencies(for request: PitchShiftRequest) -> [ExternalDependency] {
        var dependencies: [ExternalDependency] = [.ffmpeg]
        if request.processingMode == .pitchShift {
            dependencies.append(.rubberband)
        }
        if request.stemSelection != .original {
            dependencies.append(.demucs)
        }
        return dependencies
    }

    private static func requireDependencies(_ dependencies: [ExternalDependency]) throws {
        let report = ExternalDependencyReport.current()
        let missing = report.missing(dependencies)
        guard missing.isEmpty else {
            let lines = missing
                .map { "\($0.displayName): \($0.installHint)" }
                .joined(separator: "\n")
            throw CLIError.message("Missing dependencies:\n\(lines)")
        }
    }

    private static func printUsage() {
        print(usageText)
    }

    private static let usageText = """
    Usage:
      ConvertVideo2MP3CLI check-deps
      ConvertVideo2MP3CLI convert <root-directory> [--concurrency 4] [--delete-source]
      ConvertVideo2MP3CLI pitch <input.mp3> <output.mp3> [--stem original|vocals|background] [--mode pitch|export] [--direction up|down] [--semitones 2]
    """
}

private struct ArgumentParser {
    private var arguments: [String]

    init(_ arguments: [String]) {
        self.arguments = arguments
    }

    mutating func takeValue() -> String? {
        guard let index = arguments.firstIndex(where: { !$0.hasPrefix("--") }) else {
            return nil
        }
        return arguments.remove(at: index)
    }

    mutating func takeBoolFlag(_ flag: String) -> Bool {
        guard let index = arguments.firstIndex(of: flag) else {
            return false
        }
        arguments.remove(at: index)
        return true
    }

    mutating func takeIntFlag(_ flag: String) throws -> Int? {
        guard let value = try takeFlagValue(flag) else {
            return nil
        }
        guard let intValue = Int(value), intValue > 0 else {
            throw CLIError.message("\(flag) must be a positive integer.")
        }
        return intValue
    }

    mutating func takeStemFlag(_ flag: String) throws -> AudioStemSelection? {
        guard let value = try takeFlagValue(flag) else {
            return nil
        }
        switch value {
        case "original": return .original
        case "vocals": return .vocals
        case "background", "accompaniment": return .accompaniment
        default: throw CLIError.message("\(flag) must be original, vocals, or background.")
        }
    }

    mutating func takeModeFlag(_ flag: String) throws -> AudioProcessingMode? {
        guard let value = try takeFlagValue(flag) else {
            return nil
        }
        switch value {
        case "pitch": return .pitchShift
        case "export": return .exportOnly
        default: throw CLIError.message("\(flag) must be pitch or export.")
        }
    }

    mutating func takeDirectionFlag(_ flag: String) throws -> PitchShiftDirection? {
        guard let value = try takeFlagValue(flag) else {
            return nil
        }
        switch value {
        case "up": return .up
        case "down": return .down
        default: throw CLIError.message("\(flag) must be up or down.")
        }
    }

    mutating func rejectUnknownFlags() throws {
        if let unknown = arguments.first {
            throw CLIError.message("Unknown or misplaced argument: \(unknown)")
        }
    }

    private mutating func takeFlagValue(_ flag: String) throws -> String? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            throw CLIError.message("\(flag) requires a value.")
        }
        let value = arguments[valueIndex]
        arguments.remove(at: valueIndex)
        arguments.remove(at: index)
        return value
    }
}

private final class CLILogger: EventLogger {
    func log(_ level: LogLevel, event: String, details: [String: String]) {
        guard level != .debug else { return }
        let detailText = details
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        print("level=\(level.rawValue) event=\(event) \(detailText)")
    }
}

private enum CLIError: Error, LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message): return message
        }
    }
}
