import Foundation
import Testing
@testable import ConvertCore

struct MP3PlaybackTests {
    @Test func scansMP3FilesRecursivelyInListOrder() throws {
        let root = try TemporaryDirectory()
        try root.write("track-10.mp3", contents: "audio")
        try root.write("nested/track-2.MP3", contents: "audio")
        try root.write("nested/video.mp4", contents: "video")
        try root.write("notes.txt", contents: "text")

        let tracks = try MP3Scanner().scan(root: root.url)

        #expect(tracks.map(\.url.lastPathComponent) == ["track-2.MP3", "track-10.mp3"])
    }

    @Test func sortsMP3TracksByFileNameInBothDirections() throws {
        let root = try TemporaryDirectory()
        let first = try makeTrack(root: root.url, name: "track-2.mp3", bytes: 10)
        let second = try makeTrack(root: root.url, name: "track-10.mp3", bytes: 10)

        let ascending = MP3TrackSorter().sorted(
            [second, first],
            by: MP3TrackSortOption(column: .fileName, direction: .ascending)
        )
        let descending = MP3TrackSorter().sorted(
            [first, second],
            by: MP3TrackSortOption(column: .fileName, direction: .descending)
        )

        #expect(ascending.map { $0.url.lastPathComponent } == ["track-2.mp3", "track-10.mp3"])
        #expect(descending.map { $0.url.lastPathComponent } == ["track-10.mp3", "track-2.mp3"])
    }

    @Test func sortsMP3TracksByFileSizeAndKeepsMissingFilesLast() throws {
        let root = try TemporaryDirectory()
        let missing = root.url.appendingPathComponent("missing.mp3")
        let small = try makeTrack(root: root.url, name: "small.mp3", bytes: 1)
        let large = try makeTrack(root: root.url, name: "large.mp3", bytes: 100)

        let ascending = MP3TrackSorter().sorted(
            [MP3Track(url: missing), large, small],
            by: MP3TrackSortOption(column: .fileSize, direction: .ascending)
        )
        let descending = MP3TrackSorter().sorted(
            [MP3Track(url: missing), small, large],
            by: MP3TrackSortOption(column: .fileSize, direction: .descending)
        )

        #expect(ascending.map { $0.url.lastPathComponent } == ["small.mp3", "large.mp3", "missing.mp3"])
        #expect(descending.map { $0.url.lastPathComponent } == ["large.mp3", "small.mp3", "missing.mp3"])
    }

    @Test func persistsAndRestoresPlaybackPositionForExistingTrack() throws {
        let root = try TemporaryDirectory()
        let stateURL = root.url.appendingPathComponent("mp3-state.json")
        let trackURL = root.url.appendingPathComponent("episode.mp3")
        try Data("audio".utf8).write(to: trackURL)

        let store = MP3PlaybackStateStore(stateURL: stateURL)
        try store.save(MP3PlaybackPosition(trackID: trackURL.path, time: 42.5))

        let restored = try MP3PlaybackStateStore(stateURL: stateURL).load(for: [
            MP3Track(url: trackURL)
        ])

        #expect(restored == MP3PlaybackPosition(trackID: trackURL.path, time: 42.5))
    }

    @Test func ignoresPlaybackPositionWhenTrackNoLongerExistsInList() throws {
        let root = try TemporaryDirectory()
        let stateURL = root.url.appendingPathComponent("mp3-state.json")
        let oldTrackURL = root.url.appendingPathComponent("old.mp3")
        let newTrackURL = root.url.appendingPathComponent("new.mp3")
        try Data("audio".utf8).write(to: newTrackURL)

        let store = MP3PlaybackStateStore(stateURL: stateURL)
        try store.save(MP3PlaybackPosition(trackID: oldTrackURL.path, time: 12))

        let restored = try MP3PlaybackStateStore(stateURL: stateURL).load(for: [
            MP3Track(url: newTrackURL)
        ])

        #expect(restored == nil)
    }

    private func makeTrack(root: URL, name: String, bytes: Int) throws -> MP3Track {
        let url = root.appendingPathComponent(name)
        try Data(repeating: 1, count: bytes).write(to: url)
        return MP3Track(url: url)
    }
}
