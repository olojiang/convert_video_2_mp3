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
}

private final class RecordingProcessRunner: ProcessRunning {
    private(set) var commands: [(executableURL: URL, arguments: [String])] = []

    func run(
        executableURL: URL,
        arguments: [String],
        cancellation: CancellationChecking
    ) async throws -> ProcessResult {
        commands.append((executableURL, arguments))
        if let output = arguments.last, output.hasSuffix(".wav") || output.hasSuffix(".part") {
            try Data("audio".utf8).write(to: URL(fileURLWithPath: output))
        }
        return ProcessResult(exitCode: 0, output: "")
    }
}
