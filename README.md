# PocketBuild

PocketBuild 用 iPhone / iPad 为 Windows 提供源码编辑、插件和 App 编译、产物下载。基于 Dylix 的本机构建核心进行精简。

## 安装包和资源

发布一个 PocketBuild IPA。Clang、LLVM、LLD、Perl 和进程内运行支持随 App 打包并一起签名。SDK、Clang 头文件、Logos 和构建辅助资源按需下载。普通证书签名、TrollStore 和越狱安装使用同一份待签名 IPA；各安装环境的实际加载结果需要真机验收。

下载入口见 [GitHub Actions](https://github.com/qiu7c/PocketBuild/actions/workflows/build-only.yml)，选择最近成功的构建。在 Artifacts 下载 PocketBuild（内含待签名 IPA）和 PocketBuild-resources（内含资源清单、构建资源及 SDK ZIP）。

PocketBuild 最低 iOS 15.0，内嵌 arm64 编译器。当前构建入口支持 Objective-C、Objective-C++、C、C++ 和 Logos 插件，输出 dylib、deb；支持使用代码创建界面的 UIKit App，输出 .app 目录及待签名 IPA。工程导入复用 MobileCompiler.json 和受支持的 Theos Makefile 解析。Swift / SwiftUI、Storyboard、XIB、资源目录编译及完整 Xcode 工程解析尚未接入。

## 连接 Windows

1. 手机上开启个人热点，让 Windows 连接。也可以连接同一局域网。
2. 打开 PocketBuild，点「刷新地址」，选择列表中的热点或 Wi-Fi IPv4。列表未显示时可以手动填写本机地址。
3. 点击「启动服务」。在 Windows 浏览器打开手机显示的访问地址，填写手机显示的连接码。点手机上的访问地址或连接码可复制。
4. 在浏览器选择「插件 / dylib」或「UIKit App / IPA」，新建项目。App 类型会生成可编辑的 UIKit 模板。也可以上传已有工程文件夹。
5. 选择文件进行编辑，保存后点击「编译」。查看阶段和日志，结束后下载 dylib、deb、IPA、报告或日志。可在构建中请求取消。
6. 编译期间让 PocketBuild 保持前台。结束后在手机停止服务。

每次启动服务都会生成连接码。传输采用局域网 HTTP。浏览器上传使用分块暂存，完整文件收到后才替换项目文件。任务开始时复制源码快照，后续编辑用于下一次构建。

浏览器「构建设置」可以选择独立 dylib、DEB，以及有根、无根、隐根三种包类型，并设置 CPU、SDK 和最低系统版本。保存后写入 MobileCompiler.json，其余工程配置保留。可以同时选择独立 dylib 和三个 DEB；不同包布局沿用上游的链接与打包处理，实际运行需在对应环境验证。

## 用 MCP 让 AI 调用手机编译

Windows 运行 desktop/mcp_server.py，AI 客户端通过 stdio 调用它，它再通过局域网连接手机。App 内无需配置 AI 模型或 API Key。安装、配置示例、工具列表与调用顺序见 [MCP 使用教程](docs/MCP.md)。

## 编译 App 工程

先在手机安装构建资源和 iOS 16.4 SDK，再在浏览器新建「UIKit App / IPA」，即可编辑示例 main.m 和 MobileCompiler.json。最低系统版本由 deploymentTarget 决定，默认 15.0；sdkVersion 决定头文件和链接声明版本。

App 构建包含源文件编译、MH_EXECUTE 可执行文件链接、ad-hoc 签名页校验、Info.plist 生成、资源复制与 Payload/*.app 的 IPA 打包。IPA 仍需使用对应安装环境完成签名。配置和当前支持范围见 [App 工程指南](docs/APP_BUILD.md)。

## 按需安装 SDK 和头文件

先下载并解压云编译的 PocketBuild-resources 产物。解压目录内应有 PocketBuild-packages.json 以及 support、sdk16 和 sdk26 三个 ZIP。

在 Windows PowerShell 执行以下命令，将 IP 和资源目录改为实际值：

    python -m http.server 8000 --bind 172.20.10.5 --directory C:/path/to/resources

在手机「工具链」里填写资源清单地址，例如：

    http://172.20.10.5:8000/PocketBuild-packages.json

点击「读取资源清单」，选择安装构建资源和需要的 SDK。下载会显示进度，完成后校验 SHA-256 再解压安装。iOS 26 SDK 配合 Clang 14 编译 C++ 时，还需要 iOS 16.4 SDK 提供兼容的标准库头文件。清单也支持 HTTPS 地址和相对于清单的资源地址。

构建资源与 SDK 都保存在 App 数据目录，重签覆盖安装时请保留 App 数据。下载取消或校验失败会保留原先安装成功的组件。构建过程中暂停组件安装和移除。

## 构建 PocketBuild IPA

需要 macOS、Xcode 和 Python 3。先取得完整源码，以及锁定版本的编译框架：

    python3 scripts/fetch_toolchain.py
    python3 scripts/build_buildonly.py --packages

产物在 build/pocketbuild-device：

- PocketBuild-0.1.0-unsigned.ipa
- packages/PocketBuild-packages.json
- packages/PocketBuild-support-0.1.0.zip
- packages/PocketBuild-sdk16-0.1.0.zip
- packages/PocketBuild-sdk26-0.1.0.zip

IPA 使用 ad-hoc 构建签名。普通证书安装前需要对 App 和所有内嵌框架完成对应签名。可用 --package-base-url 指定资源 ZIP 的服务器目录，默认清单使用相对地址，便于在局域网直接提供下载。

脚本 --check 可在 Windows 检查构建核心提取。GitHub Actions 的 build-only.yml 使用 macOS 构建并上传 IPA 与资源包。

## 开发状态

2026-11-19，源码提交 da63fc7 通过首次 macOS 云编译，生成 PocketBuild IPA 和按需下载资源包。Windows 已通过设备 SDK 语法检查、浏览器协议模拟、真实 stdio MCP 与模拟手机 HTTP 服务联调，以及模拟 Apple 工具的安装包流程检查；macOS 已通过生产 App 打包代码配合 Xcode 工具的可执行链接、签名校验、资源布局和取消清理回归。

手机内嵌 Clang/LLD 的实际构建、真实证书签名后的安装运行、iPhone 热点连接及各越狱环境加载仍待真机验收，arm64e 状态为待验证。Windows 独立 exe 尚未实现。

上游代码和许可证保留在仓库中。PocketBuild 构建目标采用独立源文件清单，不包含上游聊天、模型服务、Agent 或 iSH 终端模块。上游项目说明见 docs/UPSTREAM_README.md，版权和第三方清单见 COPYRIGHT、LICENSE、THIRD_PARTY_NOTICES.md。
