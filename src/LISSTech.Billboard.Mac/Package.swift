// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LISSTechBillboardMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "LISSTechBillboardMac", targets: ["BillboardMac"]),
        .executable(name: "lisstech-billboard-rmm", targets: ["BillboardRMM"])
    ],
    targets: [
        .target(
            name: "BillboardShared",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ImageIO"),
                .linkedFramework("SystemConfiguration")
            ]
        ),
        .executableTarget(
            name: "BillboardMac",
            dependencies: ["BillboardShared"]
        ),
        .executableTarget(
            name: "BillboardRMM",
            dependencies: ["BillboardShared"],
            linkerSettings: [.linkedFramework("SystemConfiguration")]
        ),
        .testTarget(
            name: "BillboardSharedTests",
            dependencies: ["BillboardShared"]
        )
    ]
)
