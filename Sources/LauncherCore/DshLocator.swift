import Foundation

public enum DshLocatorError: LocalizedError {
    case missing

    public var errorDescription: String? {
        "The dsh executable was not found. Install dsh, or select its executable in Settings."
    }
}

public enum DshLocator {
    public static func resolve(configuredPath: String?, searchDirectories: [String]? = nil) throws -> URL {
        let files = FileManager.default
        if let configuredPath, !configuredPath.isEmpty {
            let expanded = (configuredPath as NSString).expandingTildeInPath
            guard expanded.hasPrefix("/"), files.isExecutableFile(atPath: expanded) else {
                throw DshLocatorError.missing
            }
            return URL(fileURLWithPath: expanded)
        }

        let directories = searchDirectories ?? defaultSearchDirectories
        for directory in directories where directory.hasPrefix("/") {
            let path = (directory as NSString).appendingPathComponent("dsh")
            if files.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        }
        if searchDirectories == nil {
            for directory in directories {
                let mise = (directory as NSString).appendingPathComponent("mise")
                guard files.isExecutableFile(atPath: mise) else { continue }
                let process = Process()
                let output = Pipe()
                process.executableURL = URL(fileURLWithPath: mise)
                process.arguments = ["which", "dsh"]
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                guard (try? process.run()) != nil else { continue }
                let path = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                process.waitUntilExit()
                if process.terminationStatus == 0 && files.isExecutableFile(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
            }
        }
        throw DshLocatorError.missing
    }

    private static var defaultSearchDirectories: [String] {
        let home = NSHomeDirectory()
        return (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/.local/share/mise/shims"]
    }
}
