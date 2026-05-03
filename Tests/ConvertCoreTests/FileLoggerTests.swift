import Testing
import Foundation
@testable import ConvertCore

struct FileLoggerTests {
    @Test func writesStructuredLogLinesWithStateDetails() throws {
        let root = try TemporaryDirectory()
        let logURL = root.url.appendingPathComponent("app.log")
        let logger = try FileEventLogger(logURL: logURL)

        logger.log(.info, event: "conversion.started", details: [
            "source": "/tmp/a.mp4",
            "status": "converting"
        ])

        Thread.sleep(forTimeInterval: 0.05)
        let content = try String(contentsOf: logURL, encoding: .utf8)
        #expect(content.contains("conversion.started"))
        #expect(content.contains("status=converting"))
        #expect(content.contains("source=/tmp/a.mp4"))
    }

    @Test func resetOnOpenClearsExistingLogFile() throws {
        let root = try TemporaryDirectory()
        let logURL = root.url.appendingPathComponent("app.log")
        try "old log".write(to: logURL, atomically: true, encoding: .utf8)

        _ = try FileEventLogger(logURL: logURL, resetOnOpen: true)

        let content = try String(contentsOf: logURL, encoding: .utf8)
        #expect(content == "")
    }
}
