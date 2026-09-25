import Foundation

public struct ServerConnection {
    public let url: URL
    public let isOwned: Bool

    public init(url: URL, isOwned: Bool) {
        self.url = url
        self.isOwned = isOwned
    }
}

public enum ServerError: LocalizedError {
    case tokenRequired
    case runningServerUnavailable
    case startupFailed(String)
    case startupTimedOut

    public var errorDescription: String? {
        switch self {
        case .tokenRequired:
            return "A running dsh server needs its token URL. Paste the URL printed by dsh web into Settings."
        case .runningServerUnavailable:
            return "A dsh server is running, but its local web port did not respond."
        case .startupFailed(let details):
            return "dsh stopped before its web server was ready. \(details)"
        case .startupTimedOut:
            return "dsh did not become ready within the startup timeout."
        }
    }
}

enum CommandOutput {
    static func run(_ executable: String, _ arguments: [String]) -> String? {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

public enum HTTPProbe {
    public static func status(_ url: URL, timeout: TimeInterval = 1.5) -> Int {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: configuration)
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let done = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var code: Int?
        let task = session.dataTask(with: request) { _, response, _ in
            lock.lock()
            code = (response as? HTTPURLResponse)?.statusCode
            lock.unlock()
            done.signal()
        }
        task.resume()
        if done.wait(timeout: .now() + timeout + 0.5) == .timedOut { task.cancel() }
        session.invalidateAndCancel()
        lock.lock(); defer { lock.unlock() }
        return code ?? 0
    }
}

public enum ServerDiscovery {
    public static func find(preferredURL: URL? = nil, onlyPID: Int32? = nil) throws -> ServerConnection? {
        guard let output = CommandOutput.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]) else {
            return nil
        }
        var candidates: [Int32: Set<Int>] = [:]
        var pid: Int32?
        for line in output.split(separator: "\n") {
            if line.first == "p" {
                pid = Int32(line.dropFirst())
            } else if line.first == "n", let pid,
                      let port = Int(line.dropFirst().split(separator: ":").last ?? ""),
                      (1...65535).contains(port) {
                candidates[pid, default: []].insert(port)
            }
        }

        var foundDsh = false
        var needsToken = false
        for pid in candidates.keys.sorted() {
            if let onlyPID, pid != onlyPID { continue }
            guard let command = CommandOutput.run("/bin/ps", ["-p", "\(pid)", "-ww", "-o", "command="]),
                  isDshCommand(command) else { continue }
            foundDsh = true
            for port in candidates[pid, default: []].sorted() {
                for host in ["127.0.0.1", "[::1]"] {
                    guard let bare = URL(string: "http://\(host):\(port)/") else { continue }
                    let status = HTTPProbe.status(bare)
                    if (200...299).contains(status) { return ServerConnection(url: bare, isOwned: false) }
                    if status == 401 {
                        needsToken = true
                        let urls = [preferredURL, startupURL(inOpenLogsOf: pid, port: port)].compactMap { $0 }
                        for url in urls where url.port == port && ServerURL.isLoopback(url) {
                            if (200...299).contains(HTTPProbe.status(url)) {
                                return ServerConnection(url: url, isOwned: false)
                            }
                        }
                    }
                }
            }
        }
        if needsToken { throw ServerError.tokenRequired }
        if foundDsh { throw ServerError.runningServerUnavailable }
        return nil
    }

    static func isDshCommand(_ command: String) -> Bool {
        command.range(of: #"(?:^|[ /])dsh(?:/lib/bin\.js)?\s+web(?:\s|$)"#,
                      options: .regularExpression) != nil
    }

    private static func startupURL(inOpenLogsOf pid: Int32, port: Int) -> URL? {
        guard let output = CommandOutput.run("/usr/sbin/lsof", ["-nP", "-a", "-p", "\(pid)", "-d", "1,2", "-Ftn"]) else {
            return nil
        }
        var regularFile = false
        for line in output.split(separator: "\n") {
            if line.first == "t" { regularFile = line == "tREG" }
            if line.first == "n", regularFile {
                let path = String(line.dropFirst())
                guard path.hasPrefix("/"), let handle = FileHandle(forReadingAtPath: path) else { continue }
                defer { try? handle.close() }
                let size = (try? handle.seekToEnd()) ?? 0
                try? handle.seek(toOffset: size > 65536 ? size - 65536 : 0)
                let tail = handle.readDataToEndOfFile()
                let lines = (String(data: tail, encoding: .utf8) ?? "").split(separator: "\n")
                for text in lines.reversed() {
                    if let url = ServerURL.fromStartupLine(String(text)), url.port == port { return url }
                }
            }
        }
        return nil
    }
}
