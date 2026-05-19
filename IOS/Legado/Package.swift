// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Legado",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "Legado",
            targets: ["Legado"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", .upToNextMajor(from: "5.8.1")),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", .upToNextMajor(from: "2.7.2")),
        .package(url: "https://github.com/groue/GRDB.swift.git", .upToNextMajor(from: "6.24.2")),
    ],
    targets: [
        .target(
            name: "Legado",
            dependencies: [
                "Alamofire",
                "SwiftSoup",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "App"),
        .testTarget(
            name: "LegadoTests",
            dependencies: ["Legado"],
            path: "Tests"),
    ]
)
