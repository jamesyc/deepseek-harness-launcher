import Cocoa
import WebKit

// Minimal chromeless windows for the DeepSeek Harness web UI.
// Usage: DeepSeek Harness <url>   (first argument is the page to open)
// File > New Window reopens the launch URL; every window shares the default
// website data store, so the token cookie works in all of them. The launcher
// owns the server lifecycle; this process exits with its last window, which
// the launcher watches to trigger its quit cascade.
final class WindowBox: NSObject {
    let window: NSWindow
    let webView: WKWebView
    var titleObservation: NSKeyValueObservation?

    init(url: URL, uiDelegate: WKUIDelegate, navigationDelegate: WKNavigationDelegate & WKDownloadDelegate, closeDelegate: NSWindowDelegate) {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: config)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        super.init()
        webView.uiDelegate = uiDelegate
        webView.navigationDelegate = navigationDelegate
        window.delegate = closeDelegate
        window.center()
        window.title = "DeepSeek Harness"
        window.contentView = webView
        titleObservation = webView.observe(\.title) { [weak window] web, _ in
            window?.title = web.title ?? "DeepSeek Harness"
        }
    }

    func show(url: URL) {
        window.makeKeyAndOrderFront(nil)
        webView.load(URLRequest(url: url))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate, WKNavigationDelegate, WKDownloadDelegate, NSWindowDelegate {
    var baseURL: URL?
    var boxes: [WindowBox] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments.dropFirst()
        guard let urlString = args.first,
              let url = URL(string: urlString),
              url.scheme == "http" || url.scheme == "https" else {
            NSApp.terminate(nil)
            return
        }
        baseURL = url
        openWindow(url)

        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileItem = NSMenuItem()
        fileItem.submenu = NSMenu(title: "File")
        fileItem.submenu?.addItem(withTitle: "New Window", action: #selector(newWindow(_:)), keyEquivalent: "n")
        mainMenu.addItem(fileItem)

        let windowItem = NSMenuItem()
        windowItem.submenu = NSMenu(title: "Window")
        windowItem.submenu?.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu?.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc func newWindow(_ sender: Any?) {
        if let url = baseURL { openWindow(url) }
    }

    func openWindow(_ url: URL) {
        let box = WindowBox(url: url, uiDelegate: self, navigationDelegate: self, closeDelegate: self)
        boxes.append(box)
        box.show(url: url)
    }

    func windowWillClose(_ notification: Notification) {
        boxes.removeAll { ($0.window === notification.object as? NSWindow) }
    }

    // Keep the windows on the harness: external links (docs, OAuth) escape to
    // the default browser instead of hijacking a chromeless window. The
    // dsh auth flows hand codes back for pasting.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame == nil,
           let url = navigationAction.request.url,
           url.scheme == "http" || url.scheme == "https" {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // Popups (sign-in flows) escape to the default browser as well.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
        return nil
    }

    // Session/log exports download to ~/Downloads instead of dying silently.
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
        } else {
            decisionHandler(.download)
        }
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let dest = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?
            .appendingPathComponent(suggestedFilename)
        completionHandler(dest)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
