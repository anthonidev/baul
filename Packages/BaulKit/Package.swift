// swift-tools-version: 6.2
import PackageDescription

/// Ajustes comunes: Swift 6 estricto + "Approachable Concurrency".
let strictConcurrency: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ExistentialAny"),
]

/// Los módulos de interfaz y de sistema viven en el main actor por defecto.
let mainActorByDefault: [SwiftSetting] = strictConcurrency + [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "BaulKit",
    defaultLocalization: "es",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "BaulCore", targets: ["BaulCore"]),
        .library(name: "BaulPersistence", targets: ["BaulPersistence"]),
        .library(name: "BaulSystem", targets: ["BaulSystem"]),
        .library(name: "BaulUI", targets: ["BaulUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.1"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
    ],
    targets: [
        // Dominio puro: sin AppKit, sin GRDB.
        .target(name: "BaulCore", swiftSettings: strictConcurrency),
        .target(
            name: "BaulPersistence",
            dependencies: ["BaulCore", .product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "BaulSystem",
            dependencies: ["BaulCore", "KeyboardShortcuts"],
            swiftSettings: mainActorByDefault
        ),
        .target(
            name: "BaulUI",
            dependencies: ["BaulCore", "BaulSystem", "KeyboardShortcuts"],
            swiftSettings: mainActorByDefault
        ),
        .testTarget(name: "BaulCoreTests", dependencies: ["BaulCore"], swiftSettings: strictConcurrency),
        .testTarget(name: "BaulUITests", dependencies: ["BaulUI", "BaulPersistence"], swiftSettings: mainActorByDefault),
        .testTarget(
            name: "BaulPersistenceTests",
            dependencies: ["BaulPersistence"],
            swiftSettings: strictConcurrency
        ),
    ]
)
