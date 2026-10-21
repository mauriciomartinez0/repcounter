// swift-tools-version: 6.0

import PackageDescription

// An xtool project contains exactly one library product, and that library is
// the app. There is no executable target: xtool wraps the library into an
// .app bundle itself, which is why @main lives inside a library here.
let package = Package(
    name: "RepCounter",
    platforms: [
        // iOS 17 is what unlocks @Observable, which every model here uses.
        // xtool reads this value and writes it into the bundle as
        // MinimumOSVersion.
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "RepCounter",
            targets: ["RepCounter"]
        ),
    ],
    targets: [
        .target(
            name: "RepCounter",
            // Barlow and Barlow Condensed (registered at launch, see
            // FontRegistry), the seed catalog and the exercise thumbnails and
            // animations.
            resources: [
                .copy("Resources/Fonts"),
                .copy("Resources/Catalog"),
                .copy("Resources/ExerciseImages"),
                .copy("Resources/ExerciseAnimations"),
                .copy("Resources/ExercisePhotos"),
            ],
            swiftSettings: [
                // Swift 5 mode: CoreBluetooth delegates are nonisolated and
                // Swift 6 strict concurrency turns the conventional delegate
                // pattern into hard errors. Models are @MainActor anyway.
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
