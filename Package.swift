// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LivePhotoSpike",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "livephoto-packager", targets: ["LivePhotoPackager"])
    ],
    targets: [
        .executableTarget(
            name: "LivePhotoPackager",
            path: "Sources/LivePhotoPackager"
        )
    ]
)
