// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Producktive", platforms: [.macOS(.v13)],
    products: [.library(name: "ProducktiveCore", targets: ["ProducktiveCore"]),
               .executable(name: "Producktive", targets: ["Producktive"]),
               .executable(name: "producktive-cli", targets: ["ProducktiveCLI"])],
    dependencies: [.package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
                   .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.0")],
    targets: [.target(name: "ProducktiveCore", dependencies: [.product(name: "Yams", package: "Yams")]),
              .executableTarget(name: "Producktive", dependencies: ["ProducktiveCore", .product(name: "Sparkle", package: "Sparkle")],
                                linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
              .executableTarget(name: "ProducktiveCLI", dependencies: ["ProducktiveCore"]),
              .testTarget(name: "ProducktiveCoreTests", dependencies: ["ProducktiveCore"])]
)
