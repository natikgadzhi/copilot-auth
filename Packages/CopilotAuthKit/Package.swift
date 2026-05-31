// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "CopilotAuthKit",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "CopilotAuthKit", targets: ["CopilotAuthKit"])
  ],
  targets: [
    .target(name: "CopilotAuthKit"),
    .testTarget(name: "CopilotAuthKitTests", dependencies: ["CopilotAuthKit"]),
  ],
  swiftLanguageModes: [.v6]
)
