// swift-tools-version: 6.2
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
    )
  ]
)
