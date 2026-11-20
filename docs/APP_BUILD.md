# 手机本机 App 工程编译

PocketBuild 支持用 Objective-C、Objective-C++、C 和 C++ 编写的代码式 UIKit App。工程用 `MobileCompiler.json` 描述单个可执行目标。在浏览器新建「UIKit App / IPA」，或用 [MCP](MCP.md) 调用 `create_project` 并传入 `product_type: "app"`，即可生成示例。

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

示例使用 arm64。构建配置也提供 arm64e 选项。此前 iOS 16.3.1 的插件试构建生成了 arm64e 对象文件，最终链接产物未通过架构校验。arm64e App 构建仍待验证。

## 构建产物

1. 用内嵌 Clang 编译源文件。
2. 使用 LLD 的可执行文件模式和 _main 入口链接，验证 MH_EXECUTE 类型和 ad-hoc 签名页哈希。
3. 组装 Payload/产品名.app，写入 Info.plist，复制配置的普通资源。
4. 打包 产品名-unsigned.ipa，保留可执行权限。浏览器或 MCP 可以下载 IPA、report.json、symbols.json 和 build.log。

浏览器、MCP 和手机「构建」页都可导出 IPA。IPA 内可执行文件带链接器生成的 ad-hoc 签名，下载后按设备的安装方式完成签名。

## 当前边界

当前编译器为 Clang/LLD 14，尚未接入 Swift/SwiftUI、完整 .xcodeproj/.xcworkspace 构建、Storyboard/XIB 编译、xcassets 编译、扩展与内嵌第三方框架签名、SPM/CocoaPods 自动依赖构建和自定义 shell 构建步骤。上述未编译资源出现在 resources 中时会报错。

可将已有 Xcode 工程中的 Objective-C/C/C++ 单目标源码及普通资源整理为 MobileCompiler.json；配置 sources 和 resources 后使用手机构建。上传只有 Xcode/Swift 工程、没有构建清单时，服务会提示当前支持范围。

## 验证

PocketBuild Build 10 已在 iOS 16.3.1 / TrollStore 环境完成 arm64 UIKit 示例的手机本机构建，并从电脑下载生成的 IPA。示例产物的安装和运行仍待单独验证。

macOS 工作流使用 `scripts/test_pocketbuild_app.py` 检查实际链接、签名检查、IPA 结构、资源复制和取消清理。开发者的验证命令见 [PocketBuild 构建指南](BUILDING.md)。
