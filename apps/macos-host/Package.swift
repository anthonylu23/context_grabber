// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ContextGrabberHost",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "ContextGrabberHost", targets: ["ContextGrabberHost"])
  ],
  targets: [
    .executableTarget(
      name: "ContextGrabberHost",
      resources: [
        .process("Resources")
      ]
    ),
    .testTarget(
      name: "ContextGrabberHostTests",
      dependencies: ["ContextGrabberHost"]
    )
  ]
)
