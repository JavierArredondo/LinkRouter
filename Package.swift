// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LinkRouter",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LinkRouter", targets: ["LinkRouter"])],
    targets: [
        .executableTarget(name: "LinkRouter", exclude: ["App/Info.plist"]),
        .testTarget(name: "LinkRouterTests", dependencies: ["LinkRouter"])
    ]
)
