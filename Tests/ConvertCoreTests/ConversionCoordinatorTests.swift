import Testing
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
}
