// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DeskPet",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PetApp",
            resources: [.copy("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
