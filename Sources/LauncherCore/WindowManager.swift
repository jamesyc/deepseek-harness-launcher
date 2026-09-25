import AppKit
import WebKit

@MainActor
public final class WindowBox: NSObject {
    public let window: NSWindow
    public let webView: WKWebView
    public let launchURL: URL
    private var titleObservation: NSKeyValueObservation?

    init(url: URL, delegate: WindowManager) {
        launchURL = url
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.title = "DeepSeek Harness"
        window.center()
        window.contentView = webView
        window.delegate = delegate
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        titleObservation = webView.observe(\.title) { [weak window] web, _ in
            window?.title = web.title ?? "DeepSeek Harness"
        }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        webView.load(URLRequest(url: launchURL))
    }
}

@MainActor
public final class WindowManager: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    public var onLastWindowClosed: (() -> Void)?
    public private(set) var baseURL: URL?
    private var boxes: [WindowBox] = []

    public var windowCount: Int { boxes.count }

    @discardableResult
    public func open(url: URL) -> WindowBox {
        baseURL = url
        let box = WindowBox(url: url, delegate: self)
        boxes.append(box)
        box.show()
        return box
    }

    @discardableResult
    public func newWindow() -> WindowBox? {
        guard let baseURL else { return nil }
        return open(url: baseURL)
    }

    public func windowWillClose(_ notification: Notification) {
        boxes.removeAll { $0.window === notification.object as? NSWindow }
        if boxes.isEmpty { onLastWindowClosed?() }
    }

    public func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url, ["http", "https"].contains(url.scheme ?? "") {
            let external = url.scheme != baseURL?.scheme || url.host != baseURL?.host || url.port != baseURL?.port
            if action.targetFrame == nil || (action.targetFrame?.isMainFrame == true && external) {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }

    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                        for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { NSWorkspace.shared.open(url) }
        return nil
    }

    public func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(response.canShowMIMEType ? .allow : .download)
    }

    public func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse,
                        didBecome download: WKDownload) {
        download.delegate = self
    }

    public func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                         suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        guard let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            completionHandler(nil)
            return
        }
        let name = (suggestedFilename as NSString).lastPathComponent
        var destination = folder.appendingPathComponent(name)
        var number = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            let stem = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            destination = folder.appendingPathComponent("\(stem) (\(number))" + (ext.isEmpty ? "" : ".\(ext)"))
            number += 1
        }
        completionHandler(destination)
    }
}
