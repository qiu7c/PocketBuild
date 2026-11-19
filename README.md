# PocketBuild

PocketBuild 用 iPhone / iPad 为 Windows 提供源码编辑、插件和 App 编译、产物下载。基于 Dylix 的本机构建核心进行精简。

## 安装包和资源

发布一个 PocketBuild IPA。Clang、LLVM、LLD、Perl 和进程内运行支持随 App 打包并一起签名。SDK、Clang 头文件、Logos 和构建辅助资源按需下载。普通证书签名、TrollStore 和越狱安装使用同一份待签名 IPA；各安装环境的实际加载结果需要真机验收。

在 [GitHub Actions](https://github.com/qiu7c/PocketBuild/actions/workflows/build-only.yml) 的构建产物中下载 PocketBuild IPA。所需组件可在 App 内直接下载。自建镜像可使用同次构建的 PocketBuild-resources 产物。

PocketBuild 最低 iOS 15.0，内嵌 arm64 编译器。当前构建入口支持 Objective-C、Objective-C++、C、C++ 和 Logos 插件，输出 dylib、deb；支持使用代码创建界面的 UIKit App，输出 .app 目录及待签名 IPA。工程导入复用 MobileCompiler.json 和受支持的 Theos Makefile 解析。Swift / SwiftUI、Storyboard、XIB、资源目录编译及完整 Xcode 工程解析尚未接入。

## 连接 Windows

1. 手机上开启个人热点，让 Windows 连接。也可以连接同一局域网。
2. 首次打开 PocketBuild，跟随介绍了解连接和配对方式，并从组件库安装所需组件。工作台会自动读取热点或 Wi-Fi IPv4，可点「刷新地址」，或在右上角「连接设置」选择或手动填写本机地址。
3. 点击「启动服务」。在 Windows 浏览器打开手机显示的访问地址，填写手机显示的连接码。点「复制地址」或「连接信息」可复制。
4. 在浏览器选择「插件 / dylib」或「UIKit App / IPA」，新建项目。App 类型会生成可编辑的 UIKit 模板。也可以上传已有工程文件夹。
5. 选择文件进行编辑，保存后点击「编译」。查看阶段和日志，结束后下载 dylib、deb、IPA、报告或日志。可在构建中请求取消。
6. 编译期间让 PocketBuild 保持前台。结束后在手机停止服务。

连接设置支持固定码与随机码。固定码保存在系统钥匙串，重启服务和 App 后继续使用；留空自动生成，也可以填写 8–64 位字母、数字、下划线或短横线。随机模式每次启动服务换码。保存的新设置在下次启动服务时生效，当前连接继续使用旧码。

工作台展示真实的服务状态、运行时长、认证请求数量、最近通信、组件就绪情况与本次启动以来最近的构建。首次引导包含开场动画，并可从「连接指南与首次配置」重看；开启系统「减弱动态效果」后不播放开场位移动画。传输采用局域网 HTTP。浏览器上传使用分块暂存，完整文件收到后才替换项目文件。任务开始时复制源码快照，后续编辑用于下一次构建。

浏览器「构建设置」可以选择独立 dylib、DEB，以及有根、无根、隐根三种包类型，并设置 CPU、SDK 和最低系统版本。保存后写入 MobileCompiler.json，其余工程配置保留。可以同时选择独立 dylib 和三个 DEB；不同包布局沿用上游的链接与打包处理，实际运行需在对应环境验证。

## 用 MCP 让 AI 调用手机编译

Windows 运行 desktop/mcp_server.py，AI 客户端通过 stdio 调用它，它再通过局域网连接手机。App 内无需配置 AI 模型或 API Key。安装、配置示例、工具列表与调用顺序见 [MCP 使用教程](docs/MCP.md)。

## 编译 App 工程

先在手机安装构建资源和 iOS 16.4 SDK，再在浏览器新建「UIKit App / IPA」，即可编辑示例 main.m 和 MobileCompiler.json。最低系统版本由 deploymentTarget 决定，默认 15.0；sdkVersion 决定头文件和链接声明版本。

App 构建包含源文件编译、MH_EXECUTE 可执行文件链接、ad-hoc 签名页校验、Info.plist 生成、资源复制与 Payload/*.app 的 IPA 打包。IPA 仍需使用对应安装环境完成签名。配置和当前支持范围见 [App 工程指南](docs/APP_BUILD.md)。

## 按需安装 SDK 和头文件

打开「组件与试编译」，按工程用途选择组件。组件库会标出必装项、下载大小和安装状态，并提供一次安装缺少组件的按钮。

| 工程用途 | 必装组件 |
| --- | --- |
| 常规构建，使用 iOS 16.4 SDK | 构建资源、iOS 16.4 SDK |
| 工程选择 iOS 26.0 SDK，使用 C、Objective-C 或 Logos `.x` | 构建资源、iOS 26.0 SDK |
| 工程选择 iOS 26.0 SDK，并包含 C++、Objective-C++ 或 Logos `.xm` | 构建资源、iOS 26.0 SDK、iOS 16.4 SDK（兼容 C++ 头文件） |

安装齐全后，可点「试编译 UIKit 示例」在手机本机编译、链接并打包示例 IPA。选择「26 + C++」会额外编译 C++ 标准库示例。试编译结束、失败或取消后清理临时工程、缓存、日志和产物，界面仅显示本次结果。App 异常退出留下的试编译目录会在下次启动时清理。

下载完成后会校验 SHA-256，再解压安装。默认下载包托管在 [PocketBuild 下载源](https://github.com/qiu7c/PocketBuild/releases/tag/resources-v1)。

若要使用局域网镜像，解压 PocketBuild-resources 云编译产物，用 PowerShell 启动 HTTP 服务。请把 IP 和目录改为实际值。

    python -m http.server 8000 --bind 172.20.10.5 --directory C:/path/to/resources

点组件库右上角的菜单，填入备用清单地址并点「启用备用源」。

    http://172.20.10.5:8000/PocketBuild-packages.json

备用清单支持 HTTPS 和局域网 HTTP，包的地址可以相对于清单填写。备用清单可只覆盖部分组件，其余组件仍使用内置源。可在同一菜单点「恢复内置源」。

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

Build 6 已在 iOS 16.3.1 / TrollStore 环境完成热点局域网 MCP 实测：上传原始 Logos 工程后，手机完成预处理、arm64 编译、链接、签名校验及有根/无根/隐根三个 DEB 打包，产物已下载并核对包内架构、目录和依赖。修复了启动命令字典遗漏、临时路径标准化不一致及诊断日志混入 Logos 源码的问题。

Build 7 增加开场动画、四步首次配置、连接设置和服务工作台，支持钥匙串固定连接码。用户已在真机确认首次引导第三步能正常显示并进入工作台；模拟器已通过固定码跨 App/服务重启、修改后延迟生效、无效码拒绝和随机模式认证验证，并取得十二张浅色/深色页面截图。托管 Intel 模拟器的冷启动、小屏幕切换和个别页面就绪等待仍出现超时，完整自动截图回归尚未通过；该检查仅在手动运行工作流时执行，自动推送继续运行编译、打包、浏览器和 MCP 回归。

arm64e 插件试构建中，Clang 生成了 CPU 子类型 2 的对象文件，链接命令返回 0，但输出未通过 arm64e 架构校验，未导出为成功产物。手机本机 App/IPA 构建、普通证书安装、插件在宿主中的运行及其他系统环境仍待验收。Windows 独立 exe 尚未实现。

上游代码和许可证保留在仓库中。PocketBuild 构建目标采用独立源文件清单，不包含上游聊天、模型服务、Agent 或 iSH 终端模块。上游项目说明见 docs/UPSTREAM_README.md，版权和第三方清单见 COPYRIGHT、LICENSE、THIRD_PARTY_NOTICES.md。
