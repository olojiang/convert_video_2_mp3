import Testing
import Foundation
@testable import ConvertCore

struct ConversionCoordinatorTests {
    @Test func runsNoMoreThanConfiguredConcurrentConversions() async throws {
        let root = try TemporaryDirectory()
        let tasks = try (0..<8).map { index -> ConversionTask in
            let source = root.url.appendingPathComponent("clip-\(index).mp4")
            let output = root.url.appendingPathComponent("clip-\(index).mp3")
            try "video".write(to: source, atomically: true, encoding: .utf8)
            return ConversionTask(video: VideoFile(sourceURL: source, outputURL: output))
        }
        let extractor = FakeAudioExtractor(delayNanoseconds: 20_000_000)
        let logger = MemoryLogger()
        let coordinator = ConversionCoordinator(extractor: extractor, logger: logger)

        let results = await coordinator.convert(tasks: tasks, concurrency: 3)

        #expect(results.filter { $0.status == .succeeded }.count == 8)
        #expect(extractor.maxActive <= 3)
        #expect(logger.events.contains { $0.event == "conversion.succeeded" })
    }

    @Test func stopPreventsPendingWorkFromStarting() async throws {
        let root = try TemporaryDirectory()
        let tasks = try (0..<6).map { index -> ConversionTask in
            let source = root.url.appendingPathComponent("stop-\(index).mov")
            let output = root.url.appendingPathComponent("stop-\(index).mp3")
            try "video".write(to: source, atomically: true, encoding: .utf8)
            return ConversionTask(video: VideoFile(sourceURL: source, outputURL: output))
        }
        let extractor = FakeAudioExtractor(delayNanoseconds: 50_000_000)
        let coordinator = ConversionCoordinator(extractor: extractor, logger: MemoryLogger())

        let run = Task {
            await coordinator.convert(tasks: tasks, concurrency: 2)
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        coordinator.requestStop()
        let results = await run.value

        #expect(extractor.startedCount < tasks.count)
        #expect(results.contains { $0.status == .cancelled || $0.status == .pending })
    }

    @Test func deletesSourceVideoWhenOptionIsEnabledAndConversionSucceeds() async throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("delete-me.mp4")
        let output = root.url.appendingPathComponent("delete-me.mp3")
        try "video".write(to: source, atomically: true, encoding: .utf8)
        let task = ConversionTask(video: VideoFile(sourceURL: source, outputURL: output))

        let coordinator = ConversionCoordinator(extractor: FakeAudioExtractor(delayNanoseconds: 1), logger: MemoryLogger())
        let results = await coordinator.convert(
            tasks: [task],
            concurrency: 1,
            options: ConversionOptions(deleteSourceOnSuccess: true)
        )

        #expect(results[0].status == .succeeded)
        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(!FileManager.default.fileExists(atPath: source.path))
    }

    @Test func publishesProgressUpdatesDuringConversion() async throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("progress.mov")
        let output = root.url.appendingPathComponent("progress.mp3")
        try "video".write(to: source, atomically: true, encoding: .utf8)
        let task = ConversionTask(video: VideoFile(sourceURL: source, outputURL: output))
        let extractor = FakeAudioExtractor(delayNanoseconds: 1, progressFractions: [0.5, 1.0])
        let updates = ProgressRecorder()
        let coordinator = ConversionCoordinator(
            extractor: extractor,
            logger: MemoryLogger(),
            onTaskUpdate: { updates.record($0) }
        )

        let results = await coordinator.convert(tasks: [task], concurrency: 1)

        #expect(results[0].progress == 1.0)
        #expect(updates.progressValues.contains(0.5))
        #expect(updates.progressValues.contains(1.0))
    }
}
