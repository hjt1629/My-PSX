// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MyPSX",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MyPSX", targets: ["MyPSX"])
    ],
    targets: [
        // 이미지 불러오기 / 편집 / 저장 로직 (UI 없음, 테스트 가능)
        .target(name: "PSXCore"),
        // SwiftUI 앱
        .executableTarget(name: "MyPSX", dependencies: ["PSXCore"]),
        .testTarget(name: "PSXCoreTests", dependencies: ["PSXCore"])
    ]
)
