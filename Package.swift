// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexQuota",
    platforms: [.macOS(.v13)],
    products: [.library(name: "CodexQuotaCore", targets: ["CodexQuotaCore"]), .executable(name: "CodexQuota", targets: ["CodexQuotaApp"])],
    targets: [
        .target(name: "CodexQuotaCore"),
        .executableTarget(name: "CodexQuotaApp", dependencies: ["CodexQuotaCore"]),
        .testTarget(name: "CodexQuotaCoreTests", dependencies: ["CodexQuotaCore"]),
        .testTarget(name: "CodexQuotaAppTests", dependencies: ["CodexQuotaApp", "CodexQuotaCore"]),
    ]
)
