# PocketBuild MCP 使用教程

AI 客户端在 Windows 上通过 stdio 启动 PocketBuild 的 MCP 桥接脚本。脚本用局域网 HTTP 连接 iPhone 或 iPad，与浏览器工作台共用地址、连接码和手机上的工程。

## 1. 准备手机和电脑

1. 让 Windows 连接 iPhone 个人热点，或让两台设备接入同一局域网。
2. 在手机「组件」安装「构建资源」和工程需要的 SDK。第一次可选「常规」，使用 iOS 16.4 SDK。
3. 在手机「工作台」点「启动服务」，记下当前访问地址和连接码。连接和构建期间将 PocketBuild 保持在前台。
4. Windows 安装 Python 3.10 或以上。把 PocketBuild 源码解压或克隆到本地，并准备一个存放待编译工程的目录。下面以 `C:/PocketBuild` 和 `C:/Projects` 为例。

```powershell
Set-Location C:/PocketBuild
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r desktop/requirements.txt
```

## 2. 添加 stdio MCP 服务器

支持 `mcpServers` JSON 的客户端可以使用下面的配置，也可以复制仓库里的[配置示例](../desktop/mcp.config.example.json)。

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
      "env": {
        "POCKETBUILD_TOKEN": "替换为手机当前连接码"
      }
    }
  }
}
```

按实际情况替换两个程序路径、手机地址、连接码及 `--workspace`。工作目录必须已存在，上传和下载都在这棵目录下。使用图形设置的客户端选择 **stdio**，分别填入 `command`、`args` 和环境变量。

配置保存后，重新加载 MCP 服务器，让客户端调用 `connect_device({})`。成功时会返回 PocketBuild 的版本、构建号、手机系统版本和组件状态。脚本由 AI 客户端启动。直接在终端运行时，它会等待 stdio 协议输入。

常用电脑可在手机「连接设置」选择固定码。修改连接码后重启手机服务，再更新客户端配置。随机模式每次启动手机服务都会换码，更新后重新加载 MCP。

## 3. 发起第一次构建

以 `C:/Projects/HelloApp` 中已有 `MobileCompiler.json` 的工程为例。

```text
connect_device({})
upload_project({"directory":"HelloApp"})
start_build({"project_id":"upload_project 返回的 project_id"})
get_build_status({"job_id":"start_build 返回的 id"})
download_artifacts({"job_id":"同一构建 id","output_directory":"artifacts"})
```

用同一个 `job_id` 查询状态。运行中可以调用 `read_build_log`，第一次传 `offset: 0`，之后使用返回的 `next_offset`。构建结束后下载，文件默认保存到 `C:/Projects/artifacts/<job_id>/`。失败时先查看状态中的 `issue` 和日志。有报告或日志产物时也可下载。

想先试模板，调用 `create_project({"name":"Demo","product_type":"app"})`，将返回的 `id` 作为 `start_build` 的 `project_id`。上传同一工程的新版本时，传入原来的 `project_id`。上传会覆盖同名文件并保留其他文件，目录整体替换可以另建项目。上传跳过 `.git`、`.theos`、`DerivedData`、`__pycache__` 和符号链接。

## 工具速查

| 工具 | 用法 |
| --- | --- |
| `connect_device` | 检查配对、版本和组件 |
| `list_projects` | 列出手机上的工程 |
| `create_project` | 创建工程。默认 `tweak`，`app` 会生成 UIKit 模板 |
| `rename_project` | 通过 `project_id` 和 `name` 修改项目显示名 |
| `list_project_files` | 列出工程内文件的相对路径 |
| `upload_project` | 上传工作目录内的工程目录。可传 `project_id` 更新现有工程，或传 `project_name` 命名新工程 |
| `read_project_file` | 用 `project_id` 和 `path` 读取 UTF-8 文件 |
| `write_project_file` | 用 `project_id`、`path` 和 `content` 保存 UTF-8 文件 |
| `start_build` | 用 `project_id` 启动构建，返回构建 `id` |
| `get_build_status` | 用 `job_id` 查询阶段、进度、问题和产物 |
| `read_build_log` | 用 `job_id` 和 `offset` 增量读取构建日志 |
| `cancel_build` | 用 `job_id` 请求在当前编译步骤后取消 |
| `list_builds` | 用 `project_id` 查看保存在手机上的历史构建 |
| `download_artifacts` | 用 `job_id` 下载本次产物，可传 `output_directory` |

## 给 AI 的指令示例

```text
用 PocketBuild MCP 编译工作目录下的 HelloApp。
先调用 connect_device 检查连接和已安装的组件，再上传工程并启动构建。
用返回的构建 ID 查询状态，必要时读取增量日志。
缺少组件时，告诉我需要在手机安装哪些组件。
编译报错时，告诉我文件、行号和报错内容，等我确认后再修改源码。
成功后把产物下载到 artifacts，给我完整的本地文件路径。
```

## 连接和构建排查

- **连接超时。** 先在 Windows 浏览器打开工作台显示的地址，再用手机「连接诊断」确认请求有没有到达。检查两台设备是否在同一网络、PocketBuild 是否在前台，以及服务是否已启动。
- **HTTP 401。** 配置的连接码与当前会话不匹配。重新复制手机工作台显示的码，并重新加载 MCP。
- **缺少组件。** 在手机「组件」安装 `issue.components` 列出的项目后重试。
- **任务返回 404。** 核对传入的是 `start_build` 返回的构建 `id`，并确认该记录仍在手机的「构建」页。
