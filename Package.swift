// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Blackmold",
    platforms: [.macOS(.v15)],
    targets: [
        // RNNoise from xiph.org (BSD-3-Clause), see Sources/CRNNoise/COPYING.
        .target(
            name: "CRNNoise",
            path: "Sources/CRNNoise",
            exclude: ["COPYING"],
            sources: ["src"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("src"),
                // Fast enough for real time even in debug builds.
                .unsafeFlags(["-O2", "-Wno-everything"]),
            ]
        ),
        // The plugin API. Library evolution and a module interface let plugins
        // compiled against one version keep working with later ones.
        .target(
            name: "BlackmoldKit",
            path: "Sources/BlackmoldKit",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-enable-library-evolution", "-emit-module-interface"]),
            ]
        ),
        .executableTarget(
            name: "Blackmold",
            dependencies: ["CRNNoise", "BlackmoldKit"],
            path: "Sources/Blackmold",
            swiftSettings: [.swiftLanguageMode(.v5)],
            // Plugins bind to BlackmoldKit's symbols in the app itself, so they stay exported.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-export_dynamic"])]
        ),
    ]
)
