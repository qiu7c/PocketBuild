# 构建 PocketBuild

## 项目目录

| 路径 | 内容 |
| --- | --- |
| App/BuildOnly | iPhone 和 iPad 原生界面、项目管理、局域网构建服务 |
| App/CompilerCore.m | 编译器框架使用的独立源码 |
| App/Remote | PocketBuild 使用的 HTTP 服务与局域网地址检查 |
| Resources/BuildWeb | 手机提供的浏览器工作台 |
| desktop | Windows 可运行的 MCP 服务与配置示例 |
| Resources/SDK、LocalSDKs/iPhoneOS26.0.sdk | 用于生成按需下载包的两套 SDK |
| Resources/AppTemplate、Resources/SampleProject | UIKit 工程模板与试编译示例 |
| Resources/PocketBuild | 应用图标与内置组件清单 |
| Vendor | 编译工具链、本机构建用的第三方代码与头文件 |
| scripts、tests | 打包命令与回归检查 |

## 生成 IPA

在安装 Xcode 和 Python 3 的 macOS 上运行：

```sh
python3 scripts/fetch_toolchain.py
python3 scripts/build_buildonly.py
```

构建产物写入 `build/pocketbuild-device/PocketBuild-0.1.0-unsigned.ipa`。Clang、LLVM、LLD、Perl 和 ios_system 框架随 IPA 打包。安装时按设备环境完成签名。

`fetch_toolchain.py` 根据 `dependencies.lock.json` 验证工具链归档和文件的 SHA-256。可以用 `--archive` 指定已下载的归档，或设定 `DYLIX_TOOLCHAIN_ROOT` 指向含 `Vendor/*.xcframework` 的目录。工具链来源与许可见 [第三方声明](../THIRD_PARTY_NOTICES.md)。

## 生成按需下载包

```sh
python3 scripts/build_buildonly.py --packages
```

输出目录为 `build/pocketbuild-device/packages/`，包含构建资源包、iOS 16.4 SDK、iOS 26.0 SDK 和资源清单。需要用独立 SDK 副本时传入 `--sdk16` 和 `--sdk26`。托管组件时，`--package-base-url` 可设置清单使用的服务器目录。

如果只需更新两个 SDK，Windows 和 macOS 都可以运行 `python scripts/build_buildonly.py --sdk-packages-only`，产物在 `build/sdk-packages/`。归档会把 SDK 内的框架和文件链接展开到编译器使用的路径。

## 本地检查

以下命令可以在 Windows 或 macOS 运行：

```sh
python scripts/build_buildonly.py --check
python scripts/test_pocketbuild.py
node scripts/test_pocketbuild_web.cjs
python -m pip install -r desktop/requirements.txt
python scripts/test_pocketbuild_mcp.py
```

在 macOS 上可额外运行 `python3 scripts/test_pocketbuild_app.py`，用 Xcode 验证真实 IPA 链接打包、项目记录、归档导入和 Makefile 清单解析。

在 Intel Mac 安装对应的 iOS 模拟器运行时后，可用 `python3 scripts/build_buildonly.py --simulator` 生成模拟器 App，再用 `python3 scripts/test_pocketbuild_ui.py` 捕获界面并核对配对流程。
