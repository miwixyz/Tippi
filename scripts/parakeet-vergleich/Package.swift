// swift-tools-version: 6.0
// Vergleich Parakeet v3 gegen Parakeet Ultra an eigenen Aufnahmen (2026-10-27).
// Eigenes kleines Paket statt Test-Ziel der App: läuft ohne Tippi, ohne die
// installierte App als Test-Host und ohne deren Einstellungen. Aufruf über
// `scripts/parakeet-vergleich.sh`.
import PackageDescription

let package = Package(
    name: "parakeet-vergleich",
    platforms: [.macOS(.v15)],
    dependencies: [
        // Gleiche Version wie die App (Package.resolved, 0.18.3).
        .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.18.3"),
    ],
    targets: [
        .target(name: "Wortfehler"),
        .executableTarget(
            name: "parakeet-vergleich",
            dependencies: ["Wortfehler", .product(name: "FluidAudio", package: "FluidAudio")]
        ),
        .testTarget(name: "WortfehlerTests", dependencies: ["Wortfehler"]),
    ],
    // Swift-5-Modus wie die App (SWIFT_VERSION 5.10).
    swiftLanguageModes: [.v5]
)
