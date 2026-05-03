import Testing
import Foundation
@testable import ConvertCore

struct TaskStateStoreTests {
    @Test func persistsSucceededTasksAndRestoresThemAcrossLaunches() throws {
        let root = try TemporaryDirectory()
        let stateURL = root.url.appendingPathComponent("state.json")
        let source = root.url.appendingPathComponent("demo.mp4")
        let output = root.url.appendingPathComponent("demo.mp3")
        try "video".write(to: source, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: output.path, contents: Data("mp3".utf8))

        let store = TaskStateStore(stateURL: stateURL)
        let task = ConversionTask(video: VideoFile(sourceURL: source, outputURL: output), status: .succeeded)
        try store.save([task])

        let restored = try TaskStateStore(stateURL: stateURL).load(for: [
            VideoFile(sourceURL: source, outputURL: output)
        ])

        #expect(restored.count == 1)
        #expect(restored[0].status == .succeeded)
        #expect(restored[0].outputURL == output)
    }

    @Test func treatsExistingOutputAsSucceededEvenWithoutPreviousState() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("fresh.mp4")
        let output = root.url.appendingPathComponent("fresh.mp3")
        try "video".write(to: source, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: output.path, contents: Data("mp3".utf8))

        let restored = try TaskStateStore(stateURL: root.url.appendingPathComponent("missing.json")).load(for: [
            VideoFile(sourceURL: source, outputURL: output)
        ])

        #expect(restored[0].status == .succeeded)
    }

    @Test func resetsFailedTasksToPendingOnLoadSoTheyCanRetry() throws {
        let root = try TemporaryDirectory()
        let stateURL = root.url.appendingPathComponent("state.json")
        let source = root.url.appendingPathComponent("retry.mp4")
        let output = root.url.appendingPathComponent("retry.mp3")
        try "video".write(to: source, atomically: true, encoding: .utf8)

        let store = TaskStateStore(stateURL: stateURL)
        try store.save([
            ConversionTask(
                video: VideoFile(sourceURL: source, outputURL: output),
                status: .failed,
                progress: 0.25,
                errorMessage: "old failure"
            )
        ])

        let restored = try TaskStateStore(stateURL: stateURL).load(for: [
            VideoFile(sourceURL: source, outputURL: output)
        ])

        #expect(restored[0].status == .pending)
        #expect(restored[0].progress == 0)
        #expect(restored[0].errorMessage == nil)
    }
}
