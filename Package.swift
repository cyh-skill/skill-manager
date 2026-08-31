// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SkillManager",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SkillManagerCore", targets: ["SkillManagerCore"]),
        .executable(name: "SkillManager", targets: ["SkillManagerApp"]),
        .executable(name: "skill-manager-cli", targets: ["SkillManagerCLI"])
    ],
    targets: [
        .target(
            name: "SkillManagerCore"
        ),
        .executableTarget(
            name: "SkillManagerApp",
            dependencies: ["SkillManagerCore"],
            exclude: ["Resources"]
        ),
        .executableTarget(
            name: "SkillManagerCLI",
            dependencies: ["SkillManagerCore"]
        ),
        .testTarget(
            name: "SkillManagerCoreTests",
            dependencies: ["SkillManagerCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
