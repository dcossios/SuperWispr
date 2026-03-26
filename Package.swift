// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SuperWispr",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SuperWispr",
            path: "SuperWisprApp",
            exclude: ["Info.plist", "SuperWispr.entitlements"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate",
                              "-Xlinker", "__TEXT",
                              "-Xlinker", "__info_plist",
                              "-Xlinker", "SuperWisprApp/Info.plist"]),
            ]
        ),
    ]
)
