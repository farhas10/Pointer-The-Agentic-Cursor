// swift-tools-version: 6.0
import PackageDescription

// This Package.swift exists ALONGSIDE the XcodeGen project (project.yml).
//
// Its purpose is CI / local compile verification: `swift build` compiles
// every source file with the same Swift 6 strict-concurrency settings as
// the app target, without depending on the Xcode IDE plugins. The shipping
// app is still built from Pointer.xcodeproj (it needs the Info.plist,
// entitlements, and app-bundle packaging that SwiftPM doesn't provide).
let package = Package(
    name: "Pointer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(
            url: "https://github.com/ChrisGVE/ExtendedSwiftMath.git",
            from: "1.0.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "Pointer",
            dependencies: [
                .product(name: "SwiftMath", package: "ExtendedSwiftMath"),
            ],
            path: "Sources/Pointer",
            exclude: [
                "Resources/Info.plist",
                "Resources/Pointer.entitlements",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "PointerTests",
            dependencies: ["Pointer"],
            path: "Tests/PointerTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
