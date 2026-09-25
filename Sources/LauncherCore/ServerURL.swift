import Foundation

public enum ServerURL {
    public static func fromStartupLine(_ line: String) -> URL? {
        guard let range = line.range(of: "dsh web: ") else { return nil }
        let value = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), isLoopback(url) else { return nil }
        return url
    }

    public static func isLoopback(_ url: URL) -> Bool {
        guard url.scheme == "http", let port = url.port, (1...65535).contains(port) else { return false }
        return ["localhost", "127.0.0.1", "::1"].contains(url.host?.lowercased() ?? "")
    }
}
