import Foundation

public enum ExternalDependency: String, CaseIterable, Equatable, Hashable {
    case ffmpeg
    case ffprobe
    case rubberband
    case demucs

    public var displayName: String {
        switch self {
        case .ffmpeg: return "ffmpeg"
        case .ffprobe: return "ffprobe"
        case .rubberband: return "Rubber Band"
        case .demucs: return "Demucs"
        }
    }

    public var purpose: String {
        switch self {
        case .ffmpeg:
            return "视频转 MP3、调音前后音频编码"
        case .ffprobe:
            return "读取视频时长，用于显示转换进度"
        case .rubberband:
            return "音乐调音"
        case .demucs:
            return "分离人声和背景音"
        }
    }

    public var installHint: String {
        switch self {
        case .ffmpeg, .ffprobe:
            return "brew install ffmpeg"
        case .rubberband:
            return "brew install rubberband"
        case .demucs:
            return "pipx install demucs"
        }
    }
}

public struct ExternalDependencyItem: Equatable {
    public let dependency: ExternalDependency
    public let executableURL: URL?

    public init(dependency: ExternalDependency, executableURL: URL?) {
        self.dependency = dependency
        self.executableURL = executableURL
    }

    public var isInstalled: Bool {
        executableURL != nil
    }
}

public struct ExternalDependencyReport: Equatable {
    public let items: [ExternalDependencyItem]

    public init(items: [ExternalDependencyItem]) {
        self.items = items
    }

    public var missing: [ExternalDependency] {
        items.filter { !$0.isInstalled }.map(\.dependency)
    }

    public var isComplete: Bool {
        missing.isEmpty
    }

    public func item(for dependency: ExternalDependency) -> ExternalDependencyItem? {
        items.first { $0.dependency == dependency }
    }

    public func missing(_ dependencies: [ExternalDependency]) -> [ExternalDependency] {
        dependencies.filter { item(for: $0)?.isInstalled != true }
    }

    public static func current() -> ExternalDependencyReport {
        ExternalDependencyReport(
            ffmpegURL: FFmpegLocator.find(),
            ffprobeURL: FFmpegLocator.findFFprobe(),
            rubberbandURL: RubberbandLocator.find(),
            demucsURL: DemucsLocator.find()
        )
    }

    public init(
        ffmpegURL: URL?,
        ffprobeURL: URL?,
        rubberbandURL: URL?,
        demucsURL: URL?
    ) {
        self.items = [
            ExternalDependencyItem(dependency: .ffmpeg, executableURL: ffmpegURL),
            ExternalDependencyItem(dependency: .ffprobe, executableURL: ffprobeURL),
            ExternalDependencyItem(dependency: .rubberband, executableURL: rubberbandURL),
            ExternalDependencyItem(dependency: .demucs, executableURL: demucsURL)
        ]
    }
}

public enum ExternalDependencyInstallerScript {
    public static func make(for missingDependencies: [ExternalDependency]) -> String {
        let uniqueMissing = Array(Set(missingDependencies))
        let needsFFmpeg = uniqueMissing.contains(.ffmpeg) || uniqueMissing.contains(.ffprobe)
        let needsRubberband = uniqueMissing.contains(.rubberband)
        let needsDemucs = uniqueMissing.contains(.demucs)

        var lines = [
            "#!/bin/zsh",
            "set -euo pipefail",
            "",
            "echo \"ConvertVideo2MP3 dependency installer\"",
            "echo \"This script installs only the tools missing from this Mac.\"",
            "",
            "ensure_homebrew() {",
            "  if command -v brew >/dev/null 2>&1; then",
            "    return",
            "  fi",
            "  echo \"Homebrew is not installed. Installing Homebrew first...\"",
            "  /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
            "  if [[ -x /opt/homebrew/bin/brew ]]; then",
            "    eval \"$(/opt/homebrew/bin/brew shellenv)\"",
            "  elif [[ -x /usr/local/bin/brew ]]; then",
            "    eval \"$(/usr/local/bin/brew shellenv)\"",
            "  fi",
            "}",
            ""
        ]

        if needsFFmpeg || needsRubberband {
            lines.append("ensure_homebrew")
        }

        if needsFFmpeg {
            lines += [
                "echo \"Installing ffmpeg and ffprobe...\"",
                "brew list ffmpeg >/dev/null 2>&1 || brew install ffmpeg",
                ""
            ]
        }

        if needsRubberband {
            lines += [
                "echo \"Installing Rubber Band...\"",
                "brew list rubberband >/dev/null 2>&1 || brew install rubberband",
                ""
            ]
        }

        if needsDemucs {
            lines += [
                "echo \"Installing Demucs...\"",
                "ensure_homebrew",
                "if ! command -v pipx >/dev/null 2>&1; then",
                "  brew list pipx >/dev/null 2>&1 || brew install pipx",
                "fi",
                "pipx ensurepath || true",
                "pipx install demucs || pipx upgrade demucs",
                ""
            ]
        }

        lines += [
            "echo \"\"",
            "echo \"Done. Reopen ConvertVideo2MP3 or click Check Dependencies again.\"",
            "echo \"If Demucs was just installed, Terminal may ask you to open a new shell before the command is on PATH; the app also checks ~/.local/bin directly.\"",
            "read \"?Press Return to close this window...\"",
            ""
        ]

        return lines.joined(separator: "\n")
    }
}
