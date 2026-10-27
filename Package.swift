// swift-tools-version:5.10
import PackageDescription

let package = Package(
  name: "SubWave",
  platforms: [.macOS("14.4")],
  targets: [
    .executableTarget(
      name: "SubWave",
      path: "Sources/SubWave",
      linkerSettings: [
        .linkedFramework("CoreAudio"),
        .linkedFramework("AudioToolbox")
      ]
    )
  ]
)
