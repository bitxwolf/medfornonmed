// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HoloMed3D",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .executable(
            name: "HoloMedApp",
            targets: ["HoloMedApp"]
        ),
        .library(
            name: "HoloMedMetal",
            targets: ["HoloMedMetal"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "HoloMedMetal",
            dependencies: [],
            path: "Sources/HoloMedMetal",
            resources: [
                .process("Shaders")
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("include")
            ]
        ),
        .executableTarget(
            name: "HoloMedApp",
            dependencies: ["HoloMedMetal"],
            path: "Sources/HoloMedApp",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
