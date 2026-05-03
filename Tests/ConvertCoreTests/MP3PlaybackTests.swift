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
}
