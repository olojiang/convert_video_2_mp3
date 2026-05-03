import Foundation
import Testing
@testable import ConvertCore

struct PartFolderCleanerTests {
    @Test func findsFoldersContainingMP4PartFiles() throws {
        let root = try TemporaryDirectory()
        try root.write("keep/video.mp4", contents: "ok")
        try root.write("broken-a/download.mp4.part", contents: "partial")
        try root.write("nested/broken-b/clip.MP4.PART", contents: "partial")
        try root.write("nested/broken-b/readme.txt", contents: "text")

        let candidates = try PartFolderCleaner().scan(root: root.url)

        #expect(candidates.map { $0.folderURL.lastPathComponent } == ["broken-a", "broken-b"])
        #expect(candidates.map(\.partFiles.count) == [1, 1])
    }

    @Test func deletesCandidateFoldersRecursively() throws {
        let root = try TemporaryDirectory()
        try root.write("broken/download.mp4.part", contents: "partial")
        try root.write("broken/sub/other.txt", contents: "text")
        let cleaner = PartFolderCleaner()
        let candidates = try cleaner.scan(root: root.url)

        let deleted = try cleaner.deleteFolders(candidates)

        #expect(deleted == 1)
        #expect(!FileManager.default.fileExists(atPath: root.url.appendingPathComponent("broken").path))
    }
}
