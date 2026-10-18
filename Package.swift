// swift-tools-version: 5.9
import Foundation
import PackageDescription

var targets: [Target] = [
    .target(name: "T150Core"),
    .executableTarget(name: "T150Updater", dependencies: ["T150Core"])
]
// The test suite is kept out of the public repository; include it only when present.
if FileManager.default.fileExists(atPath: Context.packageDirectory + "/Tests/T150CoreTests") {
    targets.append(.testTarget(name: "T150CoreTests", dependencies: ["T150Core"]))
}

let package = Package(
    name: "T150Updater",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "T150Updater", targets: ["T150Updater"]),
        .library(name: "T150Core", targets: ["T150Core"])
    ],
    targets: targets
)
