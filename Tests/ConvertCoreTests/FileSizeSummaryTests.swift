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

    @Test func sortsTasksByFileNameUsingNaturalOrder() throws {
        let root = try TemporaryDirectory()
        let first = try makeTask(root: root.url, name: "clip-2.mp4", videoBytes: 10, mp3Bytes: 1)
        let second = try makeTask(root: root.url, name: "clip-10.mp4", videoBytes: 10, mp3Bytes: 1)
        let sorted = ConversionTaskSorter().sorted(
            [second, first],
            by: ConversionTaskSortOption(column: .fileName, direction: .ascending)
        )

        #expect(sorted.map { $0.sourceURL.lastPathComponent } == ["clip-2.mp4", "clip-10.mp4"])
    }

    @Test func sortsTasksByVideoSizeInBothDirections() throws {
        let root = try TemporaryDirectory()
        let small = try makeTask(root: root.url, name: "small.mp4", videoBytes: 10, mp3Bytes: 1)
        let large = try makeTask(root: root.url, name: "large.mp4", videoBytes: 100, mp3Bytes: 1)

        let ascending = ConversionTaskSorter().sorted(
            [large, small],
            by: ConversionTaskSortOption(column: .videoSize, direction: .ascending)
        )
        let descending = ConversionTaskSorter().sorted(
            [small, large],
            by: ConversionTaskSortOption(column: .videoSize, direction: .descending)
        )

        #expect(ascending.map { $0.sourceURL.lastPathComponent } == ["small.mp4", "large.mp4"])
        #expect(descending.map { $0.sourceURL.lastPathComponent } == ["large.mp4", "small.mp4"])
    }

    @Test func sortsTasksByMP3SizeAndKeepsMissingFilesLast() throws {
        let root = try TemporaryDirectory()
        let missing = try makeTask(root: root.url, name: "missing.mp4", videoBytes: 10, mp3Bytes: nil)
        let small = try makeTask(root: root.url, name: "small.mp4", videoBytes: 10, mp3Bytes: 1)
        let large = try makeTask(root: root.url, name: "large.mp4", videoBytes: 10, mp3Bytes: 100)

        let ascending = ConversionTaskSorter().sorted(
            [missing, large, small],
            by: ConversionTaskSortOption(column: .mp3Size, direction: .ascending)
        )
        let descending = ConversionTaskSorter().sorted(
            [missing, small, large],
            by: ConversionTaskSortOption(column: .mp3Size, direction: .descending)
        )

        #expect(ascending.map { $0.sourceURL.lastPathComponent } == ["small.mp4", "large.mp4", "missing.mp4"])
        #expect(descending.map { $0.sourceURL.lastPathComponent } == ["large.mp4", "small.mp4", "missing.mp4"])
    }

    private func makeTask(root: URL, name: String, videoBytes: Int, mp3Bytes: Int?) throws -> ConversionTask {
        let video = root.appendingPathComponent(name)
        let mp3 = video.deletingPathExtension().appendingPathExtension("mp3")
        try Data(repeating: 1, count: videoBytes).write(to: video)
        if let mp3Bytes {
            try Data(repeating: 2, count: mp3Bytes).write(to: mp3)
        }
        return ConversionTask(video: VideoFile(sourceURL: video, outputURL: mp3))
    }
}
