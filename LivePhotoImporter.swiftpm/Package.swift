// swift-tools-version: 5.9

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "LivePhotoImporter",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "Live Photo Importer",
            targets: ["AppModule"],
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .star),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            capabilities: [
                .fileAccess(.userSelectedFiles, mode: .readOnly),
                .photoLibraryAdd(
                    purposeString: "Adds the selected HEIC and paired MOV to Photos as one Live Photo."
                )
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "Sources"
        )
    ]
)
