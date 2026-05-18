import Foundation

public enum ExecutableLocator {
    public static func find(named executableName: String, fixedCandidates: [String] = []) -> URL? {
        let candidates = fixedCandidates + pathCandidates(named: executableName)
        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { isRunnable($0) }
    }

    private static func pathCandidates(named executableName: String) -> [String] {
        guard let path = ProcessInfo.processInfo.environment["PATH"], !path.isEmpty else {
            return []
        }

        let extensions = executableExtensions(for: executableName)
        return path
            .split(separator: pathSeparator, omittingEmptySubsequences: true)
            .flatMap { directory in
                extensions.map { ext in
                    URL(fileURLWithPath: String(directory))
                        .appendingPathComponent(executableName + ext)
                        .path
                }
            }
    }

    private static func isRunnable(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }

    private static var pathSeparator: Character {
        #if os(Windows)
        return ";"
        #else
        return ":"
        #endif
    }

    private static func executableExtensions(for executableName: String) -> [String] {
        #if os(Windows)
        if executableName.contains(".") {
            return [""]
        }
        return [".exe", ".cmd", ".bat", ""]
        #else
        return [""]
        #endif
    }
}
