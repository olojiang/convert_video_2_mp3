import Foundation
import Testing
@testable import ConvertCore

struct FFmpegAudioExtractorIntegrationTests {
    @Test func extractsMP3WhenTemporaryOutputEndsWithPart() async throws {
        guard FFmpegLocator.find() != nil else { return }

        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("sample.mp4")
        let tempOutput = root.url.appendingPathComponent(".sample.mp3.part")
        let finalOutput = root.url.appendingPathComponent("sample.mp3")
        try makeSampleVideo(at: source)

        try await FFmpegAudioExtractor().extractMP3(
            source: source,
            tempOutput: tempOutput,
            finalOutput: finalOutput,
            cancellation: CancellationToken(),
            progress: { _ in }
        )

        #expect(FileManager.default.fileExists(atPath: finalOutput.path))
        #expect(!FileManager.default.fileExists(atPath: tempOutput.path))
    }

    private func makeSampleVideo(at url: URL) throws {
        guard let ffmpeg = FFmpegLocator.find() else { return }
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = [
            "-hide_banner",
            "-y",
            "-f", "lavfi",
            "-i", "testsrc=size=32x32:rate=1",
            "-f", "lavfi",
            "-i", "sine=frequency=1000:duration=0.3",
            "-t", "0.3",
            "-pix_fmt", "yuv420p",
            url.path
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
