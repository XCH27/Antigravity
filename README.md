# OpenClaw 图形化安装器（带 API 辅助）

这是一个 Windows 图形界面安装器示例，用来包装你的 `install.ps1 / uninstall.ps1` 等脚本，并提供一个可接入大模型 API 的“AI 辅助”面板，帮助用户排障与决策（Docker/WSL/虚拟化等）。

## 你需要准备的脚本

你的技能包/脚本组通常长这样：

- `scripts/install.ps1`
- `scripts/uninstall.ps1`（可选）

本安装器不会强依赖固定目录名，但默认会在你选择的目录里优先寻找上述文件名；也支持你在界面里手动指定脚本路径。

## 本地运行（开发/调试）

1. 安装 Python 3.10+（建议 3.11/3.12）
2. 安装依赖：

```bash
pip install -r requirements.txt
```

3. 启动：

```bash
python -m app.main
```

## 打包成 exe（单文件）

```bash
pip install pyinstaller
pyinstaller --onefile --noconsole -n OpenClawInstaller app/main.py
```

生成文件在 `dist/OpenClawInstaller.exe`。

> 本项目已内置 OpenClaw 的 `install.ps1/uninstall.ps1`（位于 `assets/`）。推荐使用 `.spec` 打包，确保脚本随 exe 一起分发。

### 推荐打包方式（内置脚本随包分发）

```bash
pip install pyinstaller
pyinstaller OpenClawInstaller.spec
```

打包产物在 `dist/OpenClawInstaller/`（目录形式），直接把整个目录发给别人即可。

如需“真正单文件”也可以，但需要额外处理资源释放；当前方案更稳、更容易排障。

## UI 增强（进度条/状态灯/步骤向导/图标）

- **步骤向导**：顶部显示 4 步（配置 API → 脚本 → 安装中 → 完成），会根据配置完整性与运行状态自动高亮
- **状态灯**：右上角圆点 + 文案（空闲/运行中/成功/失败）
- **进度条**：脚本/Agent 运行时滚动显示
- **图标**：
  - 放一个 `assets/app_icon.ico`（你自己的图标）即可在运行时作为窗口图标
  - 打包时也可在 `OpenClawInstaller.spec` 里启用 `icon="assets/app_icon.ico"` 让 exe 带图标

## AI 辅助配置（OpenAI 兼容接口）

在界面的“AI 辅助”页配置：

- **Base URL**：默认 `https://api.openai.com/v1`
- **API Key**：你的 Key
- **Model**：你的模型名（例如某些服务商会要求具体名称）

它会把“系统信息 + 最近日志 + 你的问题”发给模型。

支持两种模式：

- **仅建议模式**：返回中文排障建议（不自动执行命令）
- **Agent 自动模式**：模型输出结构化 JSON 动作，安装器按白名单动作自动执行（目前支持自动运行 `install.ps1 / uninstall.ps1` 并回传退出码与日志，循环迭代直到成功/失败）

### 支持的提供方预设与申请入口

你可以在界面里选择提供方并一键复制申请入口（或手动打开）：

- **Claude**：`https://platform.claude.com/settings/keys`
- **ChatGPT**：`https://platform.openai.com/`
- **Gemini**：`https://aistudio.google.com/api-keys`
- **Kimi**：`https://platform.moonshot.cn/console/api-keys`
- **Minimax**：`https://platform.minimaxi.com/user-center/basic-information`
- **智谱**：`https://bigmodel.cn/usercenter/proj-mgmt/apikeys`

其中：

- **Claude**：走 Anthropic 原生接口（不需要 OpenAI Base URL 形态）
- **Gemini**：走 Google 原生接口（Base URL 固定为 `https://generativelanguage.googleapis.com`，Key 通过 URL 参数传递）
- **Kimi/其他 OpenAI 兼容**：使用 OpenAI 兼容 `chat/completions`

