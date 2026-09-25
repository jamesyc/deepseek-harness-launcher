// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DeepSeekHarnessLauncher",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "DeepSeekHarnessLauncher", targets: ["DeepSeekHarnessLauncher"])],
    targets: [
        .target(name: "LauncherCore"),
        .executableTarget(name: "DeepSeekHarnessLauncher", dependencies: ["LauncherCore"]),
        .testTarget(name: "LauncherCoreTests", dependencies: ["LauncherCore"], path: "tests/LauncherCoreTests")
    ]
)
