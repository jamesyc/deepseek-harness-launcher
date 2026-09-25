import AppKit

@MainActor
public final class LauncherApplicationDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let windows = WindowManager()
    private let serviceQueue = DispatchQueue(label: "local.deepseek-harness.launcher.server")
    private var server: ServerManager?
    private var settingsWindow: SettingsWindowController?
    private var loadingWindow: NSWindow?
    private var healthTimer: Timer?
    private var connecting = false

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        windows.onLastWindowClosed = { NSApp.terminate(nil) }
        connect()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        healthTimer?.invalidate()
        guard let server else { return .terminateNow }
        serviceQueue.async {
            server.stop()
            DispatchQueue.main.async { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }

    private func connect() {
        guard !connecting else { return }
        connecting = true
        showLoading()
        let current = settings.load()
        let worker = ServerManager()
        server = worker
        serviceQueue.async { [weak self] in
            let result = Result { try worker.connect(settings: current) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { worker.stop(); return }
                self.connecting = false
                self.loadingWindow?.orderOut(nil)
                self.loadingWindow = nil
                switch result {
                case .success(let connection):
                    self.windows.open(url: connection.url)
                    if connection.isOwned {
                        self.healthTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                            Task { @MainActor [weak self] in
                                guard let self, !worker.isOwnedProcessRunning else { return }
                                self.healthTimer?.invalidate()
                                let alert = NSAlert()
                                alert.messageText = "The dsh server stopped"
                                alert.informativeText = "The server started by this app exited unexpectedly."
                                alert.runModal()
                                NSApp.terminate(nil)
                            }
                        }
                    }
                    NSApp.activate(ignoringOtherApps: true)
                case .failure(let error):
                    self.showConnectionError(error)
                }
            }
        }
    }

    private func showLoading() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 350, height: 110),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "DeepSeek Harness"
        window.isReleasedWhenClosed = false
        let spinner = NSProgressIndicator(frame: NSRect(x: 22, y: 39, width: 26, height: 26))
        spinner.style = .spinning
        spinner.startAnimation(nil)
        let label = NSTextField(labelWithString: "Connecting to dsh…")
        label.frame = NSRect(x: 62, y: 38, width: 265, height: 30)
        window.contentView?.addSubview(spinner)
        window.contentView?.addSubview(label)
        window.center()
        window.makeKeyAndOrderFront(nil)
        loadingWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showConnectionError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could not open DeepSeek Harness"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Settings")
        alert.addButton(withTitle: "Quit")
        if alert.runModal() == .alertFirstButtonReturn {
            showSettings(nil)
        } else {
            NSApp.terminate(nil)
        }
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit DeepSeek Harness", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Window", action: #selector(newWindow(_:)), keyEquivalent: "n")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }

    @objc private func newWindow(_ sender: Any?) { windows.newWindow() }

    @objc private func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let controller = SettingsWindowController(store: settings)
            controller.onSave = { [weak self] in
                guard let self, self.windows.windowCount == 0 else { return }
                self.connect()
            }
            settingsWindow = controller
        }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
