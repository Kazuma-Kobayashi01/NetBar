// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NetBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "NetBar",
            path: "Sources/NetBar",
            linkerSettings: [
                .linkedFramework("CoreWLAN"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
