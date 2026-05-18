import Foundation
import Testing
@testable import ConvertCore

struct ExternalDependencyCheckTests {
    @Test func reportsMissingDependenciesFromNilExecutableURLs() {
        let report = ExternalDependencyReport(
            ffmpegURL: URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
            ffprobeURL: nil,
            rubberbandURL: nil,
            demucsURL: URL(fileURLWithPath: "/Users/example/.local/bin/demucs")
        )

        #expect(report.missing == [.ffprobe, .rubberband])
        #expect(!report.isComplete)
        #expect(report.missing([.ffmpeg, .demucs]).isEmpty)
        #expect(report.missing([.ffprobe, .rubberband]) == [.ffprobe, .rubberband])
    }

    @Test func installerScriptInstallsFFmpegOnceWhenFFprobeIsMissing() {
        let script = ExternalDependencyInstallerScript.make(for: [.ffprobe])

        #expect(script.contains("brew install ffmpeg"))
        #expect(!script.contains("brew install rubberband"))
        #expect(!script.contains("pipx install demucs"))
    }

    @Test func installerScriptIncludesDemucsPipxPath() {
        let script = ExternalDependencyInstallerScript.make(for: [.demucs])

        #expect(script.contains("brew install pipx"))
        #expect(script.contains("pipx install demucs || pipx upgrade demucs"))
    }
}
