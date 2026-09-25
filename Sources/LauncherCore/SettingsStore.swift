import Foundation
import Security

public struct LauncherSettings: Equatable, Sendable {
    public var dshPath: String?
    public var workspacePath: String
    public var existingServerURL: String?

    public init(dshPath: String? = nil,
                workspacePath: String = NSHomeDirectory() + "/.dsh/workspace",
                existingServerURL: String? = nil) {
        self.dshPath = dshPath
        self.workspacePath = workspacePath
        self.existingServerURL = existingServerURL
    }
}

public enum SettingsError: LocalizedError {
    case invalidServerURL
    case invalidWorkspace
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL: return "The existing server URL must be an HTTP loopback URL with a port."
        case .invalidWorkspace: return "Choose a workspace directory."
        case .keychain(let status): return "Could not save the server URL in Keychain (\(status))."
        }
    }
}

public final class ServerURLSecretStore {
    private let service: String

    public init(service: String = "local.deepseek-harness.window") { self.service = service }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "existing-server-url"]
    }

    public func load() -> String? {
        var item: CFTypeRef?
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ value: String?) throws {
        if let value {
            let data = Data(value.utf8)
            let status: OSStatus
            if load() == nil {
                var request = query
                request[kSecValueData as String] = data
                status = SecItemAdd(request as CFDictionary, nil)
            } else {
                status = SecItemUpdate(query as CFDictionary,
                                       [kSecValueData as String: data] as CFDictionary)
            }
            if status != errSecSuccess { throw SettingsError.keychain(status) }
        } else {
            delete()
        }
    }

    public func delete() { SecItemDelete(query as CFDictionary) }
}

public final class SettingsStore {
    private let defaults: UserDefaults
    private let secrets: ServerURLSecretStore

    public init(defaults: UserDefaults = .standard, secrets: ServerURLSecretStore = .init()) {
        self.defaults = defaults
        self.secrets = secrets
    }

    public func load() -> LauncherSettings {
        LauncherSettings(dshPath: defaults.string(forKey: "dshPath"),
                         workspacePath: defaults.string(forKey: "workspacePath") ?? NSHomeDirectory() + "/.dsh/workspace",
                         existingServerURL: secrets.load())
    }

    public func save(_ settings: LauncherSettings) throws {
        let workspace = (settings.workspacePath as NSString).expandingTildeInPath
        if !workspace.hasPrefix("/") {
            throw SettingsError.invalidWorkspace
        }
        let manualURL = settings.existingServerURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let manualURL, !manualURL.isEmpty {
            guard let url = URL(string: manualURL), ServerURL.isLoopback(url) else {
                throw SettingsError.invalidServerURL
            }
        }
        try secrets.save(manualURL?.isEmpty == true ? nil : manualURL)
        defaults.set(settings.dshPath?.isEmpty == true ? nil : settings.dshPath, forKey: "dshPath")
        defaults.set(settings.workspacePath, forKey: "workspacePath")
    }
}
