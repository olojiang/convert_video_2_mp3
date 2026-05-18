import Foundation
import Testing
@testable import ConvertCore

struct RubberbandPitchShifterTests {
    @Test func runsFFmpegRubberbandAndFFmpegWithSignedPitch() async throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("song.mp3")
        let output = root.url.appendingPathComponent("song-up-2.mp3")
        try Data("mp3".utf8).write(to: source)

        let runner = RecordingProcessRunner()
        let shifter = RubberbandPitchShifter(
            ffmpegURL: URL(fileURLWithPath: "/usr/bin/ffmpeg"),
            rubberbandURL: URL(fileURLWithPath: "/usr/bin/rubberband"),
            demucsURL: URL(fileURLWithPath: "/usr/bin/demucs"),
            runner: runner
        )

        var progressValues: [Double] = []
        try await shifter.shiftPitch(
            request: PitchShiftRequest(sourceURL: source, outputURL: output, direction: .up, semitones: 2),
            cancellation: CancellationToken(),
            progress: { progressValues.append($0) }
        )

        #expect(runner.commands.count == 3)
        #expect(runner.commands[0].executableURL.path == "/usr/bin/ffmpeg")
        #expect(Array(runner.commands[0].arguments.suffix(2)).first == source.path)
        #expect(runner.commands[1].executableURL.path == "/usr/bin/rubberband")
        #expect(Array(runner.commands[1].arguments[0...1]) == ["-p", "2"])
        #expect(runner.commands[2].executableURL.path == "/usr/bin/ffmpeg")
        #expect(runner.commands[2].arguments.contains { $0.hasSuffix(".song-up-2.mp3.part") })
        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(progressValues == [1.0 / 3.0, 2.0 / 3.0, 1.0])
    }

    @Test func downDirectionPassesNegativePitchToRubberband() async throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("song.mp3")
        let output = root.url.appendingPathComponent("song-down-3.mp3")
        try Data("mp3".utf8).write(to: source)

        let runner = RecordingProcessRunner()
        let shifter = RubberbandPitchShifter(
            ffmpegURL: URL(fileURLWithPath: "/usr/bin/ffmpeg"),
            rubberbandURL: URL(fileURLWithPath: "/usr/bin/rubberband"),
            demucsURL: URL(fileURLWithPath: "/usr/bin/demucs"),
            runner: runner
        )

        try await shifter.shiftPitch(
            request: PitchShiftRequest(sourceURL: source, outputURL: output, direction: .down, semitones: 3),
            cancellation: CancellationToken(),
            progress: { _ in }
        )

        #expect(Array(runner.commands[1].arguments[0...1]) == ["-p", "-3"])
    }

    @Test func validatesSourceAndSemitoneCountBeforeRunningCommands() async throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("song.txt")
        let output = root.url.appendingPathComponent("song.mp3")
        try Data("text".utf8).write(to: source)

        let runner = RecordingProcessRunner()
        let shifter = RubberbandPitchShifter(
            ffmpegURL: URL(fileURLWithPath: "/usr/bin/ffmpeg"),
            rubberbandURL: URL(fileURLWithPath: "/usr/bin/rubberband"),
            demucsURL: URL(fileURLWithPath: "/usr/bin/demucs"),
            runner: runner
        )

        await #expect(throws: PitchShiftError.invalidSource) {
            try await shifter.shiftPitch(
                request: PitchShiftRequest(sourceURL: source, outputURL: output, direction: .up, semitones: 1),
                cancellation: CancellationToken(),
                progress: { _ in }
            )
        }

        #expect(runner.commands.isEmpty)
    }

    @Test func separatesVocalsWithDemucsBeforePitchShiftingSelectedStem() async throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("song.mp3")
        let output = root.url.appendingPathComponent("song-vocals-up-2.mp3")
        try Data("mp3".utf8).write(to: source)

        let runner = RecordingProcessRunner()
        let shifter = RubberbandPitchShifter(
            ffmpegURL: URL(fileURLWithPath: "/usr/bin/ffmpeg"),
            rubberbandURL: URL(fileURLWithPath: "/usr/bin/rubberband"),
            demucsURL: URL(fileURLWithPath: "/usr/bin/demucs"),
            runner: runner
        )

        var progressValues: [Double] = []
        try await shifter.shiftPitch(
            request: PitchShiftRequest(
                sourceURL: source,
                outputURL: output,
                direction: .up,
                semitones: 2,
                stemSelection: .vocals
            ),
            cancellation: CancellationToken(),
            progress: { progressValues.append($0) }
        )

        #expect(runner.commands.count == 4)
        #expect(runner.commands[0].executableURL.path == "/usr/bin/demucs")
        #expect(runner.commands[0].arguments.contains("--two-stems"))
        #expect(runner.commands[0].arguments.contains("vocals"))
        #expect(runner.commands[1].executableURL.path == "/usr/bin/ffmpeg")
        #expect(runner.commands[1].arguments.contains { $0.hasSuffix("/vocals.wav") })
        #expect(runner.commands[2].executableURL.path == "/usr/bin/rubberband")
        #expect(runner.commands[3].executableURL.path == "/usr/bin/ffmpeg")
        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(progressValues == [0.25, 0.5, 0.75, 1.0])
    }

    @Test func requiresDemucsOnlyWhenStemSeparationIsRequested() async throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("song.mp3")
        let output = root.url.appendingPathComponent("song-vocals.mp3")
        try Data("mp3".utf8).write(to: source)

        let shifter = RubberbandPitchShifter(
            ffmpegURL: URL(fileURLWithPath: "/usr/bin/ffmpeg"),
            rubberbandURL: URL(fileURLWithPath: "/usr/bin/rubberband"),
            demucsURL: nil,
            runner: RecordingProcessRunner()
        )

        await #expect(throws: PitchShiftError.demucsNotFound) {
            try await shifter.shiftPitch(
                request: PitchShiftRequest(
                    sourceURL: source,
                    outputURL: output,
                    direction: .up,
                    semitones: 1,
                    stemSelection: .accompaniment
                ),
                cancellation: CancellationToken(),
                progress: { _ in }
            )
        }
    }

    @Test func exportsSeparatedBackgroundWithoutRunningRubberband() async throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("song.mp3")
        let output = root.url.appendingPathComponent("song-background.mp3")
        try Data("mp3".utf8).write(to: source)

        let runner = RecordingProcessRunner()
        let shifter = RubberbandPitchShifter(
            ffmpegURL: URL(fileURLWithPath: "/usr/bin/ffmpeg"),
            rubberbandURL: URL(fileURLWithPath: "/usr/bin/rubberband"),
            demucsURL: URL(fileURLWithPath: "/usr/bin/demucs"),
            runner: runner
        )

        var progressValues: [Double] = []
        try await shifter.shiftPitch(
            request: PitchShiftRequest(
                sourceURL: source,
                outputURL: output,
                direction: .up,
                semitones: 6,
                stemSelection: .accompaniment,
                processingMode: .exportOnly
            ),
            cancellation: CancellationToken(),
            progress: { progressValues.append($0) }
        )

        #expect(runner.commands.count == 2)
        #expect(runner.commands[0].executableURL.path == "/usr/bin/demucs")
        #expect(runner.commands[1].executableURL.path == "/usr/bin/ffmpeg")
        #expect(runner.commands[1].arguments.contains { $0.hasSuffix("/no_vocals.wav") })
        #expect(!runner.commands.contains { $0.executableURL.path == "/usr/bin/rubberband" })
        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(progressValues == [0.5, 1.0])
    }

    @Test func exportOnlyOriginalDoesNotRequireRubberband() async throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("song.mp3")
        let output = root.url.appendingPathComponent("song-original.mp3")
        try Data("mp3".utf8).write(to: source)

        let runner = RecordingProcessRunner()
        let shifter = RubberbandPitchShifter(
            ffmpegURL: URL(fileURLWithPath: "/usr/bin/ffmpeg"),
            rubberbandURL: nil,
            demucsURL: nil,
            runner: runner
        )

        var progressValues: [Double] = []
        try await shifter.shiftPitch(
            request: PitchShiftRequest(
                sourceURL: source,
                outputURL: output,
                direction: .up,
                semitones: 0,
                processingMode: .exportOnly
            ),
            cancellation: CancellationToken(),
            progress: { progressValues.append($0) }
        )

        #expect(runner.commands.count == 1)
        #expect(runner.commands[0].executableURL.path == "/usr/bin/ffmpeg")
        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(progressValues == [1.0])
    }
}

private final class RecordingProcessRunner: ProcessRunning {
    private(set) var commands: [(executableURL: URL, arguments: [String])] = []

    func run(
        executableURL: URL,
        arguments: [String],
        cancellation: CancellationChecking
    ) async throws -> ProcessResult {
        commands.append((executableURL, arguments))
        if executableURL.path.hasSuffix("/demucs") {
            try writeDemucsOutputs(arguments: arguments)
        }
        if let output = arguments.last, output.hasSuffix(".wav") || output.hasSuffix(".part") {
            try Data("audio".utf8).write(to: URL(fileURLWithPath: output))
        }
        return ProcessResult(exitCode: 0, output: "")
    }

    private func writeDemucsOutputs(arguments: [String]) throws {
        guard let outIndex = arguments.firstIndex(of: "--out"),
              arguments.indices.contains(outIndex + 1),
              let inputPath = arguments.last else {
            return
        }

        let outputDirectory = URL(fileURLWithPath: arguments[outIndex + 1])
        let source = URL(fileURLWithPath: inputPath)
        let stemDirectory = outputDirectory
            .appendingPathComponent("htdemucs", isDirectory: true)
            .appendingPathComponent(source.deletingPathExtension().lastPathComponent, isDirectory: true)
        try FileManager.default.createDirectory(at: stemDirectory, withIntermediateDirectories: true)
        try Data("vocals".utf8).write(to: stemDirectory.appendingPathComponent("vocals.wav"))
        try Data("background".utf8).write(to: stemDirectory.appendingPathComponent("no_vocals.wav"))
    }
}
