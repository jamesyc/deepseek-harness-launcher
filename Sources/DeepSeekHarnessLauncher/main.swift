import AppKit
import LauncherCore

@main
struct LauncherMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = LauncherApplicationDelegate()
        app.delegate = delegate
        app.run()
    }
}
