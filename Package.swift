// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Flotilla",

    platforms: [
        .macOS(.v15),
    ],

    dependencies: [
        // 代码规范：提供 `swift package format` 命令插件
        .package(url: "https://github.com/RakuyoKit/swift.git", exact: "1.4.0"),
    ],

    targets: [
        .executableTarget(
            name: "Flotilla",

            exclude: [
                // 由打包脚本拷入 .app，不参与编译
                "Info.plist",
            ]
        ),

        .testTarget(
            name: "FlotillaTests",
            dependencies: ["Flotilla"]
        ),
    ]
)
