import Foundation
import Testing
@testable import ConvertCore

struct FileSizeSummaryTests {
    @Test func readsFileSizesAndSummarizesVideoAndMP3Bytes() throws {
        let root = try TemporaryDirectory()
        let video = root.url.appendingPathComponent("clip.mp4")
        let mp3 = root.url.appendingPathComponent("clip.mp3")
        try Data(repeating: 1, count: 1_500).write(to: video)
        try Data(repeating: 2, count: 500).write(to: mp3)

        let task = ConversionTask(video: VideoFile(sourceURL: video, outputURL: mp3))
        let summary = FileSizeReader().summary(for: [task])

        #expect(summary.videoBytes == 1_500)
        #expect(summary.mp3Bytes == 500)
    }

    @Test func formatsBytesForDisplay() {
        #expect(FileSizeText.format(nil) == "-")
        #expect(FileSizeText.format(0) == "0 B")
        #expect(FileSizeText.format(512) == "512 B")
        #expect(FileSizeText.format(1_536) == "1.50 KB")
        #expect(FileSizeText.format(1_048_576) == "1.00 MB")
    }
}
