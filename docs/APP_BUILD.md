# 手机本机 App 工程编译

当前路径支持 Objective-C、Objective-C++、C、C++ 与通过代码创建界面的 UIKit App。工程通过 MobileCompiler.json 描述单个可执行目标。浏览器选择「UIKit App / IPA」或 MCP create_project 的 product_type=app 可生成示例。

## 配置示例

```json
{
  "productType": "app",
  "productName": "HelloPocket",
  "bundleIdentifier": "com.example.hellopocket",
  "sources": ["main.m", "ViewController.m", "Logic.cpp"],
  "frameworks": ["Foundation", "UIKit"],
  "resources": ["assets", "config.json"],
  "appInfoPlist": "Info.plist",
  "sdkVersion": "16.4",
  "deploymentTarget": "15.0",
  "cpuArchitecture": "arm64",
  "objcArc": true,
  "package": false
}
```

sources 列出的源码必须存在于工程内。resources 可省略，使用工程内文件或目录的相对路径，会保留相对目录结构复制到 App 中。appInfoPlist 可省略，提供时会合并用户的显示名、权限说明等属性；可执行名称、Bundle ID、最低系统版本和包类型由构建配置生成。

productName 使用字母开头，仅含字母、数字、下划线和短横线；该名称用作可执行文件和 .app 目录名。需要中文应用名时在 Info.plist 中设置 CFBundleDisplayName。

App 构建固定输出待签名 IPA，package/exportDylib 为插件构建选项，不控制 App 产物。默认生成支持 iPhone 和 iPad 的 Info.plist。

## 系统和 SDK

PocketBuild 本身最低 iOS 15.0。生成的 App 由 deploymentTarget 指定最低版本，当前允许至少 15.0 且不高于所选 SDK。使用更高版本 API 时仍需在源码处理系统可用性。

先安装构建资源与至少一套 SDK。可选 SDK 16.4 或 26.0。SDK 26.0 配合当前 Clang 14 处理 C++/Objective-C++ 时还需要 SDK 16.4 的标准库兼容头文件。

构建配置保留 arm64 和 arm64e。arm64e 当前状态为待验证：上游代码在链接后检查 Mach-O 的 CPU 子类型，发现与 arm64e 不符时会报错并停止导出。尚未使用这套手机内嵌工具链生成、检查并在真机加载 arm64e 产物，不能仅凭源码中的注释判断实际支持结果。需要检查实际产物的架构与 ABI，并完成目标宿主中的加载和运行验证。

## 构建产物

1. 用内嵌 Clang 编译源文件。
2. 使用 LLD 的可执行文件模式和 _main 入口链接，验证 MH_EXECUTE 类型和 ad-hoc 签名页哈希。
3. 组装 Payload/产品名.app，写入 Info.plist，复制配置的普通资源。
4. 打包 产品名-unsigned.ipa，保留可执行权限。浏览器或 MCP 可以下载 IPA、report.json、symbols.json 和 build.log。

完整 .app 保存在手机 Documents/Build-任务目录/Payload 中，可通过文件共享访问。IPA 内可执行文件有链接器生成的 ad-hoc 签名，但没有安装用的证书签名与描述文件。下载后按实际安装方式完成签名，安装和运行需要真机验证。

## 当前边界

当前编译器为 Clang/LLD 14，尚未接入 Swift/SwiftUI、完整 .xcodeproj/.xcworkspace 构建、Storyboard/XIB 编译、xcassets 编译、扩展与内嵌第三方框架签名、SPM/CocoaPods 自动依赖构建和自定义 shell 构建步骤。上述未编译资源出现在 resources 中时会报错。

可将已有 Xcode 工程中的 Objective-C/C/C++ 单目标源码及普通资源整理为 MobileCompiler.json；配置 sources 和 resources 后使用手机构建。上传只有 Xcode/Swift 工程、没有构建清单时，服务会提示当前支持范围。

## 验证

Windows 已检查原生代码语法及 MCP、浏览器传输流程。macOS 可运行 python3 scripts/test_pocketbuild_app.py，使用生产打包代码和 Xcode 工具检查可执行链接参数、签名验证、IPA 元数据、资源布局、权限与取消清理。该测试已加入云编译，但本机没有 Xcode，尚未实际执行；它也不代替 iPhone 内嵌 Clang/LLD 编译与安装验收。
