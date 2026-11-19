# PocketBuild MCP 使用教程

连接路径是 AI 客户端 → Windows 上的 stdio MCP 进程 → 手机 PocketBuild 的局域网 HTTP 服务。浏览器与 MCP 共用同一套服务、连接码和工程。手机 App 不包含聊天界面，也不需要模型账号。

## 准备

手机最低 iOS 15.0，保持 PocketBuild 前台运行。安装构建资源和需要的 SDK。Windows 连接手机个人热点或与手机处于同一局域网。在 PocketBuild 启动服务，记下显示的访问地址和当前连接码。

Windows 安装 Python 3.10 或以上版本。以下示例假定源码在 C:/PocketBuild，允许 AI 操作的本地工程目录为 C:/Projects。

```powershell
cd C:/PocketBuild
python -m venv .venv
.venv/Scripts/python.exe -m pip install -r desktop/requirements.txt
```

## 客户端配置

支持 mcpServers JSON 配置的客户端可参考 desktop/mcp.config.example.json。替换 Python 路径、脚本路径、手机访问地址、工作目录及连接码。

```json
{
  "mcpServers": {
    "PocketBuild": {
      "command": "C:/PocketBuild/.venv/Scripts/python.exe",
      "args": [
        "C:/PocketBuild/desktop/mcp_server.py",
        "--phone", "http://172.20.10.1:8787",
        "--workspace", "C:/Projects"
      ],
      "env": {"POCKETBUILD_TOKEN": "手机上显示的当前连接码"}
    }
  }
}
```

其他客户端选择 stdio 传输，分别填写同样的 command、args 和环境变量。手机地址以 App 实际显示值为准。每次重启手机服务会刷新连接码，更新配置后重启客户端中的 MCP 进程。

该桥使用官方 [MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk/tree/v1.x) 的 FastMCP 和 stdio 传输，依赖限制在 v1 系列。单独在终端启动时等待协议输入是正常现象，实际由 AI 客户端启动并调用。

## 工具及调用顺序

| 工具 | 用途 |
| --- | --- |
| connect_device | 检查连接、手机系统版本、构建组件安装状态 |
| list_projects | 列出手机工程 |
| create_project | 新建工程，product_type 为 tweak 或 app；app 附带 UIKit 模板 |
| list_project_files | 列出工程文件 |
| upload_project | 将本地工作目录中的子目录上传到手机，可传 project_id 更新已有工程 |
| read_project_file | 读取手机上的 UTF-8 文件 |
| write_project_file | 分块保存 UTF-8 文件 |
| start_build | 启动构建，返回 id |
| get_build_status | 用 job_id 查询状态、阶段、进度和产物列表 |
| read_build_log | 用 job_id、offset 读取日志；下次使用 next_offset |
| cancel_build | 请求取消指定任务，当前工具步骤结束后生效 |
| download_artifacts | 下载指定任务产物到本地工作目录下 |

已有工程示例。

```text
connect_device({})
upload_project({"directory":"HelloApp"})
start_build({"project_id":"上传返回的 project_id"})
get_build_status({"job_id":"构建返回的 id"})
read_build_log({"job_id":"同一个 id","offset":0})
download_artifacts({"job_id":"同一个 id","output_directory":"artifacts"})
```

从模板开始时先 create_project({"name":"Demo","product_type":"app"})，再列出、读取和修改文件。上传已有工程会逐文件覆盖同名文件，不删除手机上的其他文件；完整替换工程时新建空工程后上传。上传本地 App 工程也可以直接使用 upload_project，它会新建空工程并采用上传的 MobileCompiler.json。

返回状态包括 running、succeeded、failed、cancelled。只有构建完成后下载产物。失败时也可下载报告和日志。任务编号可区分本次启动 App 以来的多次构建，手机 App 重启后任务编号失效。产物仍保留在手机 Documents/Build-* 目录。

上传排除 .git、.theos、DerivedData、__pycache__ 和符号链接。本地上传和下载限制在 --workspace 内，局域网请求绕过 Windows 的 HTTP 代理。

## 给 AI 的指令示例

```text
使用 PocketBuild MCP，把工作目录中的 HelloApp 编译为 iPhone App。
先调用 connect_device 检查连接和 SDK，再读取工程 MobileCompiler.json。
使用手机当前支持的 Objective-C/C/C++ 与 UIKit 构建路径。
上传工程后启动构建，保存返回的任务 id，用这个 id 查询状态和增量日志。
失败时先读取报告和错误位置，修改源码后重新构建。
成功后将 IPA、报告和日志下载到 artifacts，并告诉我本地文件路径。
需要 Swift、Storyboard 或其他当前不支持的构建步骤时，明确指出缺少的能力。
```

## 连接排查

- 先用 Windows 浏览器打开手机显示的地址。浏览器也打不开时检查手机前台状态、选中的热点地址和 Windows 网络连接。
- HTTP 401 表示连接码不匹配。手机停止再启动服务后需要更新连接码。
- 提示缺少 SDK 或构建资源时，在手机工具链页面安装组件。
- 指定任务返回 404 时检查是否使用了另一任务编号，或手机 App 是否重启。
- MCP 传输测试使用模拟手机服务；真实设备的网络、签名加载和编译结果仍需实际验收。
