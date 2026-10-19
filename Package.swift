// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenLamp",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "OpenLampKit", targets: ["OpenLampKit"]),
        .executable(name: "OpenLamp", targets: ["OpenLamp"]),
        .executable(name: "probe", targets: ["probe"]),
    ],
    targets: [
        .target(
            name: "OpenLampKit",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "OpenLamp",
            dependencies: ["OpenLampKit"]
        ),
        .executableTarget(
            name: "probe",
            dependencies: ["OpenLampKit"]
        ),
        .testTarget(
            name: "OpenLampKitTests",
            dependencies: ["OpenLampKit"]
        ),
    ]
)
