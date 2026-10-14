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

        // 更新检查、签名校验与安装使用同一套发布协议
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.0"),
    ],

    targets: [
        .executableTarget(
            name: "Flotilla",

            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],

            exclude: [
                // 由打包脚本拷入 .app，不参与编译
                "Info.plist",
                "Resources",
            ],

            linkerSettings: [
                // 打包后从 App 自身的 Frameworks 目录加载更新框架
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),

        // Dock tile 的 stub 可执行文件：由打包脚本拷入 Flotilla.app，再由 Flotilla 拷进每个 stub bundle
        .executableTarget(name: "FlotillaDockTile"),

        .testTarget(
            name: "FlotillaTests",
            dependencies: ["Flotilla"]
        ),
    ]
)
