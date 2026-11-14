// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MelcolmAIO",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MelcolmAIO",
            path: "Sources/MelcolmAIO",
            linkerSettings: [
                .linkedFramework("CoreWLAN"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreAudio"),
            ]
        ),
    ]
)
