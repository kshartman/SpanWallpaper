// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpanWallpaper",
    platforms: [.macOS(.v11)],
    targets: [
        .target(
            name: "SpanWallpaperLib",
            path: "Sources/SpanWallpaperLib"
        ),
        .executableTarget(
            name: "SpanWallpaper",
            dependencies: ["SpanWallpaperLib"],
            path: "Sources/SpanWallpaper",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreImage"),
            ]
        ),
        .testTarget(
            name: "SpanWallpaperTests",
            dependencies: ["SpanWallpaperLib"],
            path: "Tests/SpanWallpaperTests"
        ),
    ]
)
