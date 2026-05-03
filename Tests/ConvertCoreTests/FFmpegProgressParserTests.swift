import Testing
@testable import ConvertCore

struct FFmpegProgressParserTests {
    @Test func convertsOutTimeToProgressFractionWhenDurationIsKnown() {
        let parser = FFmpegProgressParser(durationSeconds: 10)

        let values = parser.parse("""
        frame=1
        out_time_ms=5000000
        progress=continue
        """)

        #expect(values == [0.5])
    }

    @Test func reportsOneWhenFFmpegProgressEnds() {
        let parser = FFmpegProgressParser(durationSeconds: nil)

        let values = parser.parse("progress=end\n")

        #expect(values == [1.0])
    }
}
