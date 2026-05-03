import Testing
@testable import ConvertCore

struct VideoScannerTests {
    @Test func findsSupportedVideosRecursivelyAndDerivesMP3OutputBesideSource() throws {
        let root = try TemporaryDirectory()
        try root.write("clip-a.mp4", contents: "video")
        try root.write("nested/clip-b.MOV", contents: "video")
        try root.write("nested/readme.txt", contents: "text")

        let videos = try VideoScanner().scan(root: root.url)

        #expect(videos.map(\.sourceURL.lastPathComponent) == ["clip-a.mp4", "clip-b.MOV"])
        #expect(videos.map(\.outputURL.lastPathComponent) == ["clip-a.mp3", "clip-b.mp3"])
        #expect(videos[1].outputURL.path.contains("/nested/"))
    }
}
