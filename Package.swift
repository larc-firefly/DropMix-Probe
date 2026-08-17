// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DropMixBLEProbe",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "DropMixBLEProbe",
            path: ".",
            exclude: [
                "README.md",
                "PROTOCOL_NOTES.md",
                "captures",
                "DropMixProbeXcode.xcworkspace"
            ]
        )
    ]
)
