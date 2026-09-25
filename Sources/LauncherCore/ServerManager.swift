import Foundation
import Darwin

private final class StartupOutput {
    private let lock = NSLock()
    private var pending = Data()
    private var foundURL: URL?
    private var messages: [String] = []

    var url: URL? {
        lock.lock(); defer { lock.unlock() }
        return foundURL
    }

    var details: String {
        lock.lock(); defer { lock.unlock() }
        return messages.suffix(3).joined(separator: " ")
    }

    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        pending.append(data)
        while let newline = pending.firstIndex(of: 10) {
            let line = String(data: pending[..<newline], encoding: .utf8) ?? ""
            pending.removeSubrange(...newline)
            if let url = ServerURL.fromStartupLine(line) { foundURL = url }
            let redacted = line.replacingOccurrences(of: #"token=[^&\s]+"#, with: "token=[redacted]",
                                                     options: .regularExpression)
            if !redacted.isEmpty { messages.append(redacted) }
            if messages.count > 10 { messages.removeFirst(messages.count - 10) }
        }
        if pending.count > 65536 { pending.removeFirst(pending.count - 65536) }
    }
}

// The app calls connect and stop on one serial service queue.
public final class ServerManager: @unchecked Sendable {
    private let environment: [String: String]
    private let discover: (URL?) throws -> ServerConnection?
    private let processLock = NSLock()
    private var process: Process?
    private var output: Pipe?

    public init(environment: [String: String] = [:],
                discover: @escaping (URL?) throws -> ServerConnection? = { try ServerDiscovery.find(preferredURL: $0) }) {
        self.environment = environment
        self.discover = discover
    }

    public var isOwnedProcessRunning: Bool {
        processLock.lock(); defer { processLock.unlock() }
        return process?.isRunning == true
    }

    public func connect(settings: LauncherSettings, discoverExisting: Bool = true,
                        timeout: TimeInterval = 30) throws -> ServerConnection {
        let executable = try DshLocator.resolve(configuredPath: settings.dshPath)
        if discoverExisting,
           let existing = try discover(settings.existingServerURL.flatMap(URL.init(string:))) {
            return existing
        }

        let workspace = (settings.workspacePath as NSString).expandingTildeInPath
        try FileManager.default.createDirectory(atPath: workspace, withIntermediateDirectories: true)
        let child = Process()
        let pipe = Pipe()
        let startup = StartupOutput()
        child.executableURL = executable
        child.arguments = ["web", "--no-open", "--port", "0"]
        child.currentDirectoryURL = URL(fileURLWithPath: workspace)
        child.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        child.standardOutput = pipe
        child.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { startup.append(data) }
        }
        do {
            try child.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }
        processLock.lock()
        process = child
        processLock.unlock()
        output = pipe

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let url = startup.url, HTTPProbe.status(url) == 200 {
                return ServerConnection(url: url, isOwned: true)
            }
            if !child.isRunning {
                let details = startup.details
                stop()
                throw ServerError.startupFailed(details)
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        stop()
        throw ServerError.startupTimedOut
    }

    public func stop() {
        processLock.lock()
        let child = process
        processLock.unlock()
        guard let child else { return }
        if child.isRunning { child.terminate() }
        let deadline = Date().addingTimeInterval(5)
        while child.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if child.isRunning { _ = Darwin.kill(child.processIdentifier, SIGKILL) }
        child.waitUntilExit()
        output?.fileHandleForReading.readabilityHandler = nil
        output = nil
        processLock.lock()
        process = nil
        processLock.unlock()
    }

    deinit { stop() }
}
