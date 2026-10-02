// swift-tools-version:5.10
// Spike 2026-10-02: Live-Diktat mit dem vorhandenen Parakeet TDT v3 — siehe README.md.
// Gleiche FluidAudio-Version wie Tippi (Package.resolved: 0.15.2, 7f963cd).
import PackageDescription
let package = Package(
    name: "Spike",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.2")],
    targets: [.executableTarget(name: "Spike", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")])]
)
