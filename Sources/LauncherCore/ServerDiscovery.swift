import Foundation
import Darwin

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
        guard ServerURL.isLoopback(url), let host = url.host, let port = url.port,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return 0 }
        let addresses = host == "::1" ? ["::1"] : host == "localhost" ? ["127.0.0.1", "::1"] : ["127.0.0.1"]
        let path = (components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath)
            + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
        let authority = host == "::1" ? "[::1]:\(port)" : "\(host):\(port)"
        let request = Array("GET \(path) HTTP/1.1\r\nHost: \(authority)\r\nConnection: close\r\n\r\n".utf8)

        for address in addresses {
            let family = address == "::1" ? AF_INET6 : AF_INET
            let descriptor = Darwin.socket(family, SOCK_STREAM, 0)
            guard descriptor >= 0 else { continue }
            defer { Darwin.close(descriptor) }
            var deadline = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout.truncatingRemainder(dividingBy: 1)) * 1_000_000))
            withUnsafePointer(to: &deadline) {
                _ = Darwin.setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
                _ = Darwin.setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
            }
            let connected: Int32
            if family == AF_INET6 {
                var socketAddress = sockaddr_in6()
                socketAddress.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
                socketAddress.sin6_family = sa_family_t(AF_INET6)
                socketAddress.sin6_port = in_port_t(port).bigEndian
                _ = address.withCString { Darwin.inet_pton(AF_INET6, $0, &socketAddress.sin6_addr) }
                connected = withUnsafePointer(to: &socketAddress) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
                    }
                }
            } else {
                var socketAddress = sockaddr_in()
                socketAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                socketAddress.sin_family = sa_family_t(AF_INET)
                socketAddress.sin_port = in_port_t(port).bigEndian
                _ = address.withCString { Darwin.inet_pton(AF_INET, $0, &socketAddress.sin_addr) }
                connected = withUnsafePointer(to: &socketAddress) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            guard connected == 0 else { continue }
            var sent = 0
            while sent < request.count {
                let count = request.withUnsafeBytes {
                    Darwin.send(descriptor, $0.baseAddress!.advanced(by: sent), request.count - sent, 0)
                }
                if count <= 0 { break }
                sent += count
            }
            guard sent == request.count else { continue }
            var response = [UInt8]()
            while response.count < 1024 && !response.contains(10) {
                var bytes = [UInt8](repeating: 0, count: 256)
                let count = Darwin.recv(descriptor, &bytes, bytes.count, 0)
                if count <= 0 { break }
                response.append(contentsOf: bytes.prefix(count))
            }
            let firstLine = String(decoding: response, as: UTF8.self).split(separator: "\n").first ?? ""
            let words = firstLine.split(separator: " ")
            if words.count >= 2, let code = Int(words[1]) { return code }
        }
        return 0
    }
}

public enum ServerDiscovery {
    public static func find(preferredURL: URL? = nil, onlyPID: Int32? = nil) throws -> ServerConnection? {
        var arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]
        if let onlyPID { arguments += ["-a", "-p", "\(onlyPID)"] }
        guard let output = CommandOutput.run("/usr/sbin/lsof", arguments) else {
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
