// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MarqetKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "MarqetCore", targets: ["MarqetCore"]),
        .library(name: "MarqetReminders", targets: ["MarqetReminders"]),
        .library(name: "MarqetPersistence", targets: ["MarqetPersistence"]),
    ],
    targets: [
        // Pure domain logic – Foundation only, fully unit-testable.
        .target(
            name: "MarqetCore",
            resources: [.process("Resources")]
        ),
        // EventKit access behind the ReminderGateway protocol.
        .target(
            name: "MarqetReminders",
            dependencies: ["MarqetCore"]
        ),
        // SwiftData persistence of the user's stores.
        .target(
            name: "MarqetPersistence",
            dependencies: ["MarqetCore"]
        ),
        .testTarget(name: "MarqetCoreTests", dependencies: ["MarqetCore"]),
        .testTarget(name: "MarqetRemindersTests", dependencies: ["MarqetReminders"]),
        .testTarget(name: "MarqetPersistenceTests", dependencies: ["MarqetPersistence"]),
    ]
)
