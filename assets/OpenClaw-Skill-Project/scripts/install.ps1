# OpenClaw-Skill-Project/scripts/install.ps1
param (
    [switch]$CheckOnly
)

function Write-Header {
    param($text)
    Write-Host "`n=== $text ===" -ForegroundColor Cyan
}

Write-Host "OpenClaw 官方: https://openclaw.ai/" -ForegroundColor Gray
Write-Host "GitHub: https://github.com/openclaw/openclaw" -ForegroundColor Gray

# 0. 安装痕迹记录路径 (必须统一保存在 WSL 内，才能与 Linux/macOS 以及卸载脚本统一)
# 注意：路径直接在 WSL 命令中使用 ~ 展开，PowerShell 侧不需处理

# 1. 环境全自动预检与修复
Write-Header "正在为您准备环境 (请稍候...)"
$wslStatus = wsl --status 2>&1
if ($wslStatus -match "没有安装" -or $wslStatus -match "is not installed") {
    Write-Host "[!] 未检测到 WSL 环境，正在尝试自动为您开启 (可能需要管理员权限)..." -ForegroundColor Yellow
    # 尝试自动安装 WSL (最简命令)
    Start-Process powershell -ArgumentList "wsl --install --no-distribution" -Verb RunAs -Wait
    Write-Host "WSL 核心组件已提交安装请求。请重启电脑后再次运行此脚本以继续。" -ForegroundColor Green
    Write-Host "官网直达修复方案: https://openclaw.ai/install" -ForegroundColor Gray
    exit 0
}

# 虚拟化检查 (最直白的报错)
$virtualization = (Get-WmiObject -Query "Select * from Win32_Processor").VHVMCapabilities
if (!$virtualization) {
    Write-Host "`n[🚨 关键错误] 您的电脑未开启 '虚拟化技术 (VT-x/AMD-V)'。" -ForegroundColor Red
    Write-Host "这是龙虾运行的必备条件。请在主板 BIOS 中开启它。" -ForegroundColor White
    Write-Host "简单教程: 重启电脑点按 F2/Del -> 进入 BIOS -> 找 Virtualization -> 选 Enabled。" -ForegroundColor Gray
    exit 1
}

if ($CheckOnly) { Write-Host "环境就绪。" ; exit 0 }

# 2. 部署模式与隔离方案确认
Write-Header "选择部署模式与运行环境"
Write-Host "OpenClaw 建议运行在隔离环境中以确保您的宿主系统安全。" -ForegroundColor Yellow
Write-Host "请选择您的安装方案：" -ForegroundColor White

Write-Host "`n[隔离/虚拟环境方案 - 推荐]" -ForegroundColor Green
Write-Host "1. Docker 容器安装 (运行在独立的沙盒内，预装国内 IM 插件，最安全)"
Write-Host "2. WSL 原生安装 (运行在 Windows 的 Linux 子系统中，环境完全隔离，轻量)"

Write-Host "`n[非隔离方案]" -ForegroundColor Gray
Write-Host "3. 云端 VPS 资源指引 (如果您希望完全脱离本机在远程运行)"

$mode = Read-Host "请选择模式 (1/2/3)"

if ($mode -eq "3") {
    Write-Header "云端部署引导"
    Write-Host "云端部署通常在远程服务器 (如 Ubuntu/Debian) 上执行。" -ForegroundColor Yellow
    
    Write-Host "`n--- 火山引擎 ---" -ForegroundColor Cyan
    Write-Host "入口: 一键部署OpenClaw - 火山引擎"
    Write-Host "教程: https://www.volcengine.com/docs/6462/1161048"

    Write-Host "`n--- 腾讯云 ---" -ForegroundColor Cyan
    Write-Host '入口: https://cloud.tencent.com/act/pro/lighthouse-moltbot?from=29437&Is=home'
    Write-Host "教程: https://cloud.tencent.com/developer/article/2624973"

    Write-Host "`n--- 阿里云 ---" -ForegroundColor Cyan
    Write-Host "入口: OpenClaw - 9.9元定制7*24 AI助理 - 阿里云"
    Write-Host "教程: 部署OpenClaw镜像并构建钉钉AI员工"

    Write-Host "`n--- 百度智能云 ---" -ForegroundColor Cyan
    Write-Host "入口: https://cloud.baidu.com/product/BCC/moltbot.html"
    Write-Host "教程: https://cloud.baidu.com/doc/LS/s/6ml9f3cvl"

    Write-Host "`n[通用教程]" -ForegroundColor Gray
    Write-Host "VPS 部署详细指南: https://github.com/xianyu110/awesome-openclaw-tutorial/blob/main/appendix/A-vps-deployment.md"
    exit 0
}

# 4. 安全配置引导
Write-Header "安全配置引导"
Write-Host "!!! 密钥安全提醒: 严禁在任何公共日志或不安全的命令行历史中明文传递 API Key。" -ForegroundColor Yellow
Write-Host "建议按照以下步骤安全操作："
Write-Host "1. 在 WSL 中创建配置文件: mkdir -p ~/.config/clawdbot"
Write-Host "2. 使用编辑器安全写入密钥: nano ~/.config/clawdbot/config.json"
Write-Host "3. 设置严格的文件权限: chmod 600 ~/.config/clawdbot/config.json"

# 5. API 配置交互式向导
Write-Header "API 配置向导"
Write-Host "OpenClaw 需要配置 LLM API 才能正常工作。" -ForegroundColor White
Write-Host "请选择您的 API 提供商：" -ForegroundColor Cyan
Write-Host ""
Write-Host "[国内 API - 网络稳定]" -ForegroundColor Green
Write-Host "  1. Kimi (月之暗面)     - https://platform.moonshot.cn/"
Write-Host "  2. 智谱 AI (Zhipu)     - https://bigmodel.cn/"
Write-Host "  3. MiniMax (稀宇)     - https://platform.minimaxi.com/"
Write-Host ""
Write-Host "[国外 API - 能力更强]" -ForegroundColor Yellow
Write-Host "  4. Claude (Anthropic)  - https://platform.claude.com/"
Write-Host "  5. OpenAI (ChatGPT)   - https://platform.openai.com/"
Write-Host "  6. Google Gemini      - https://aistudio.google.com/"
Write-Host ""
Write-Host "  7. 暂不配置 (稍后手动配置)"

$apiChoice = Read-Host "`n请选择 (1-7)"

$apiConfig = ""
switch ($apiChoice) {
    "1" { # Kimi
        Write-Host ""
        Write-Host "=== Kimi API 配置指南 ===" -ForegroundColor Green
        Write-Host "1. 访问 https://platform.moonshot.cn/ 注册/登录"
        Write-Host "2. 进入「API 密钥管理」创建新密钥"
        Write-Host "3. 复制密钥并妥善保存（只显示一次）"
        Write-Host ""
        Write-Host "模型推荐: moonshot-v1-8k" -ForegroundColor Cyan
        $apiConfig = "KIMI"
    }
    "2" { # 智谱
        Write-Host ""
        Write-Host "=== 智谱 AI API 配置指南 ===" -ForegroundColor Green
        Write-Host "1. 访问 https://bigmodel.cn/ 注册/登录"
        Write-Host "2. 进入「API 密钥」创建新密钥"
        Write-Host "3. 复制密钥并妥善保存"
        Write-Host ""
        Write-Host "模型推荐: glm-4" -ForegroundColor Cyan
        $apiConfig = "ZHIPU"
    }
    "3" { # MiniMax
        Write-Host ""
        Write-Host "=== MiniMax API 配置指南 ===" -ForegroundColor Green
        Write-Host "1. 访问 https://platform.minimaxi.com/ 注册/登录"
        Write-Host "2. 进入「开发者后台」创建 API Key"
        Write-Host "3. 复制密钥并妥善保存"
        Write-Host ""
        Write-Host "模型推荐: abab6.5s-chat" -ForegroundColor Cyan
        $apiConfig = "MINIMAX"
    }
    "4" { # Claude
        Write-Host ""
        Write-Host "=== Claude API 配置指南 ===" -ForegroundColor Green
        Write-Host "1. 访问 https://platform.claude.com/ 注册/登录"
        Write-Host "2. 进入「Settings」→ 「API Keys」创建密钥"
        Write-Host "3. 复制密钥并妥善保存"
        Write-Host ""
        Write-Host "模型推荐: claude-3-5-sonnet-20241022" -ForegroundColor Cyan
        $apiConfig = "CLAUDE"
    }
    "5" { # OpenAI
        Write-Host ""
        Write-Host "=== OpenAI API 配置指南 ===" -ForegroundColor Green
        Write-Host "1. 访问 https://platform.openai.com/ 注册/登录"
        Write-Host "2. 进入「API Keys」创建新密钥"
        Write-Host "3. 复制密钥并妥善保存"
        Write-Host ""
        Write-Host "模型推荐: gpt-4o" -ForegroundColor Cyan
        $apiConfig = "OPENAI"
    }
    "6" { # Gemini
        Write-Host ""
        Write-Host "=== Google Gemini API 配置指南 ===" -ForegroundColor Green
        Write-Host "1. 访问 https://aistudio.google.com/app/apikey"
        Write-Host "2. 创建新 API 密钥"
        Write-Host "3. 复制密钥并妥善保存"
        Write-Host ""
        Write-Host "模型推荐: gemini-1.5-pro" -ForegroundColor Cyan
        $apiConfig = "GEMINI"
    }
    "7" {
        Write-Host "已跳过 API 配置，稍后可运行 'clawdbot config api' 重新配置" -ForegroundColor Yellow
        $apiConfig = "SKIP"
    }
    default {
        Write-Host "无效选择，已跳过 API 配置" -ForegroundColor Yellow
        $apiConfig = "SKIP"
    }
}

if ($apiConfig -ne "SKIP" -and $apiConfig -ne "") {
    Write-Host ""
    Write-Host "配置方法：" -ForegroundColor Cyan
    Write-Host "  clawdbot config api $apiConfig"
    Write-Host ""
    Write-Host "或手动写入配置文件: ~/.config/clawdbot/config.json" -ForegroundColor Gray
}

# 生成安装记录，供后续智能卸载使用
wsl -e bash -c "mkdir -p ~/.config/clawdbot"
$installLog = @{
    InstallDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Mode = $mode
    OS = "Windows (WSL)"
    ApiProvider = $apiConfig
    Services = @("OpenClaw Core")
}
$jsonString = $installLog | ConvertTo-Json -Compress

# 将 JSON 写入 WSL 路径 (使用双引号让 PowerShell 展开变量)
wsl -e bash -c "echo '$jsonString' > ~/.config/clawdbot/install_report.json"

Write-Host "`n安装工作流执行完毕。安装记录已保存至 (WSL): ~/.config/clawdbot/install_report.json" -ForegroundColor Green

# 6. 龙虾技能安装准备 (必备与专业技能推荐)
Write-Header "龙虾技能商店推荐 (建议安装)"
Write-Host "环境配置已就绪，您可以根据您的职业和兴趣选择以下专业技能："

Write-Host "`n[💻 深度研发]" -ForegroundColor Cyan
Write-Host "- Project Summary      : 极其强大的代码库概览与分析"
Write-Host "- Jarvis Codebase      : 自动理清复杂项目的架构与入口"

Write-Host "`n[🎬 视频剪辑]" -ForegroundColor Cyan
Write-Host "- ffmpeg-video-editor  : 用大白话控制 FFmpeg 进行视频剪辑"
Write-Host "- Video Frames         : 快速提取视频帧素材"

Write-Host "`n[📈 股市监控]" -ForegroundColor Cyan
Write-Host "- Stock Analysis       : 深度趋势检测与投资组合管理"
Write-Host "- Stock Watcher        : 对接同花顺，管理国内自选股"

Write-Host "`n[📅 高效办公]" -ForegroundColor Cyan
Write-Host "- AI Meeting Notes     : 瞬间通过录音生成带待办的会议摘要"
Write-Host "- Coordinate Meeting   : AI 自动代劳协调多人会议时间"

Write-Host "`n[💬 IM 平台官方配置教程]" -ForegroundColor Cyan
Write-Host "- QQ       : https://q.qq.com/qqbot/openclaw/login.html"
Write-Host "- 企业微信 : https://work.weixin.qq.com/nl/index/openclaw"
Write-Host "- 钉钉     : https://open.dingtalk.com/document/dingstart/build-dingtalk-ai-employees"
Write-Host "- 飞书     : https://bytedance.larkoffice.com/docx/MFK7dDFLFoVlOGxWCv5cTXKmnMh"

Write-Host "`n[安装方法]" -ForegroundColor Gray
Write-Host "在您的 WSL 终端运行: clawdbot skill install [作者]/[名称]"
Write-Host "详情参见: https://clawhub.ai/"

if ($mode -eq "1") {
    # Docker 容器安装 (隔离环境 - 推荐)
    Write-Header "Docker 模式安装"
    $dockerCheck = docker version 2>&1
    if (!$dockerCheck -or $dockerCheck -match "error") {
        Write-Error "错误: 未检测到 Docker 环境。请先安装 Docker Desktop。"
        exit 1
    }
    Write-Host "正在下载 Docker 配置并启动..."
    # 实际执行逻辑：wget/curl 仓库下的 docker-compose.yml
    Write-Host "参考项目: https://github.com/justlovemaki/OpenClaw-Docker-CN-IM" -ForegroundColor Green

    # 尝试自动拉取编排文件跑起来
    wsl -e bash -c 'mkdir -p ~/openclaw-docker && cd ~/openclaw-docker && curl -fsSL -O https://raw.githubusercontent.com/justlovemaki/OpenClaw-Docker-CN-IM/main/docker-compose.yml && docker compose up -d'

    # 安装后验证
    Write-Header "验证 Docker 容器运行状态"
    Start-Sleep -Seconds 5
    $dockerStatus = docker ps --filter "name=clawdbot" --format "{{.Status}}"
    if ($dockerStatus -match "Up") {
        Write-Host "✅ OpenClaw 容器已成功启动并正在运行。状态: $dockerStatus" -ForegroundColor Green
    } else {
        Write-Host "⚠️ OpenClaw 容器启动可能失败或仍在初始加载中。请通过 'docker logs clawdbot' 查看详情。" -ForegroundColor Yellow
    }

    exit 0
}

# WSL 原生安装 (mode == "2")
Write-Header "执行 WSL 静默安装"
Write-Host "正在调用 WSL 执行官方一键安装脚本..."
wsl -e bash -c "curl -fsSL https://openclaw.ai/install.sh | bash"
Write-Host "原生安装步骤已下发执行结束。"

# 安装后验证
Write-Header "验证 WSL 原生安装状态"
$binCheck = wsl -e bash -c "command -v clawdbot"
if ($binCheck) {
    $ver = wsl -e bash -c "clawdbot --version"
    Write-Host "✅ OpenClaw 原生安装完成！版本: $ver" -ForegroundColor Green

    # 自动安装必备技能 (仅原生模式)
    Write-Header "正在安装必备技能"
    Write-Host "根据 SKILL.md 规范，自动安装必备技能..." -ForegroundColor Yellow

    $coreSkills = @("self-improving-agent", "tavily-search", "GitHub", "weather", "find-skills", "proactive-agent")
    foreach ($skill in $coreSkills) {
        Write-Host -NoNewline "安装 $skill ... "
        $result = wsl -e bash -c "clawdbot skill install $skill 2>/dev/null" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓" -ForegroundColor Green
        } else {
            Write-Host "跳过" -ForegroundColor Yellow
        }
    }
    Write-Host "必备技能安装完成！" -ForegroundColor Green

    # Web UI 可选安装
    Write-Header "Web UI 图形界面 (可选)"
    Write-Host "OpenClaw 支持以下 Web UI 方案：" -ForegroundColor White
    Write-Host ""
    Write-Host "[1] 安装 Web Dashboard (社区版)" -ForegroundColor Cyan
    Write-Host "    命令: clawdbot skill install openclaw/web-dashboard"
    Write-Host ""
    Write-Host "[2] 启动内置 Web 服务 (如支持)" -ForegroundColor Cyan
    Write-Host "    命令: clawdbot web"
    Write-Host ""
    Write-Host "[3] 跳过 (默认)" -ForegroundColor Gray
    Write-Host ""

    $webuiChoice = Read-Host "请选择是否安装 Web UI (1/2/3)"

    if ($webuiChoice -eq "1") {
        Write-Host "正在安装 Web Dashboard..." -ForegroundColor Yellow
        wsl -e bash -c "clawdbot skill install openclaw/web-dashboard 2>/dev/null" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "未找到该技能，请尝试其他方案" -ForegroundColor Yellow
        }
    } elseif ($webuiChoice -eq "2") {
        Write-Host "尝试启动内置 Web 服务..." -ForegroundColor Yellow
        wsl -e bash -c "clawdbot web --help 2>/dev/null" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "内置 Web 服务不可用" -ForegroundColor Yellow
        }
    }

    # IM 绑定交互式向导
    Write-Header "即时通讯 (IM) 绑定向导"
    Write-Host "将 OpenClaw 连接到 IM 平台，即可通过微信/QQ/钉钉等与它对话" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "请选择要绑定的平台:" -ForegroundColor Cyan
    Write-Host "  1. QQ        (国内最常用)"
    Write-Host "  2. 飞书      (字节跳动)"
    Write-Host "  3. 钉钉      (阿里系)"
    Write-Host "  4. 企业微信  (腾讯系)"
    Write-Host "  5. Telegram  (国际版)"
    Write-Host "  6. Discord   (国际版)"
    Write-Host "  7. 暂不绑定  (以后再说)"
    Write-Host ""

    $imChoice = Read-Host "请选择 (1-7)"

    switch ($imChoice) {
        "1" {
            Write-Host ""
            Write-Host "=== QQ 绑定指南 ===" -ForegroundColor Green
            Write-Host "1. 打开 https://q.qq.com/qqbot/openclaw/login.html"
            Write-Host "2. 使用 QQ 扫码登录"
            Write-Host "3. 创建或选择一个 OpenClaw Bot"
            Write-Host "4. 获取 AppID 和 Token"
            Write-Host ""
            Write-Host "完成后，运行以下命令配置:" -ForegroundColor Cyan
            Write-Host "  clawdbot config im qq"
        }
        "2" {
            Write-Host ""
            Write-Host "=== 飞书绑定指南 ===" -ForegroundColor Green
            Write-Host "1. 打开 https://bytedance.larkoffice.com/docx/MFK7dDFLFoVlOGxWCv5cTXKmnMh"
            Write-Host "2. 创建企业应用"
            Write-Host "3. 添加机器人并获取 App ID 和 App Secret"
            Write-Host "4. 配置事件订阅和权限"
            Write-Host ""
            Write-Host "完成后，运行以下命令配置:" -ForegroundColor Cyan
            Write-Host "  clawdbot config im feishu"
        }
        "3" {
            Write-Host ""
            Write-Host "=== 钉钉绑定指南 ===" -ForegroundColor Green
            Write-Host "1. 打开 https://open.dingtalk.com/document/dingstart/build-dingtalk-ai-employees"
            Write-Host "2. 创建企业内部开发应用"
            Write-Host "3. 添加机器人并获取 AppKey 和 AppSecret"
            Write-Host "4. 配置机器人权限"
            Write-Host ""
            Write-Host "完成后，运行以下命令配置:" -ForegroundColor Cyan
            Write-Host "  clawdbot config im dingtalk"
        }
        "4" {
            Write-Host ""
            Write-Host "=== 企业微信绑定指南 ===" -ForegroundColor Green
            Write-Host "1. 打开 https://work.weixin.qq.com/nl/index/openclaw"
            Write-Host "2. 创建企业微信应用"
            Write-Host "3. 获取 CorpID 和 Secret"
            Write-Host "4. 配置应用权限"
            Write-Host ""
            Write-Host "完成后，运行以下命令配置:" -ForegroundColor Cyan
            Write-Host "  clawdbot config im wecom"
        }
        "5" {
            Write-Host ""
            Write-Host "=== Telegram 绑定指南 ===" -ForegroundColor Green
            Write-Host "1. 打开 https://t.me/BotFather"
            Write-Host "2. 发送 /newbot 创建新机器人"
            Write-Host "3. 获取 Bot Token"
            Write-Host "4. 与 @userinfobot 对话获取你的 User ID"
            Write-Host ""
            Write-Host "完成后，运行以下命令配置:" -ForegroundColor Cyan
            Write-Host "  clawdbot config im telegram"
        }
        "6" {
            Write-Host ""
            Write-Host "=== Discord 绑定指南 ===" -ForegroundColor Green
            Write-Host "1. 打开 https://discord.com/developers/applications"
            Write-Host "2. 创建新应用"
            Write-Host "3. 添加 Bot 用户并获取 Token"
            Write-Host "4. 配置 intents 权限"
            Write-Host "5. 复制 Client ID 并邀请机器人到服务器"
            Write-Host ""
            Write-Host "完成后，运行以下命令配置:" -ForegroundColor Cyan
            Write-Host "  clawdbot config im discord"
        }
        "7" {
            Write-Host "已跳过 IM 绑定，稍后可运行 'clawdbot config im' 重新配置" -ForegroundColor Yellow
        }
        default {
            Write-Host "无效选择，已跳过 IM 绑定" -ForegroundColor Yellow
        }
    }

    if ($imChoice -ne "7" -and $imChoice -ne "") {
        Write-Host ""
        Write-Host "配置完成后，重启 OpenClaw 即可生效:" -ForegroundColor Green
        Write-Host "  clawdbot restart"
    }

    # 首次启动指南
    Write-Header "🚀 首次启动指南"
    Write-Host "恭喜！OpenClaw 安装完成！" -ForegroundColor Green
    Write-Host ""
    Write-Host "【启动 OpenClaw】" -ForegroundColor White
    Write-Host "  在 WSL 中运行: clawdbot"
    Write-Host ""
    Write-Host "【开始对话】" -ForegroundColor White
    Write-Host "  在终端直接输入你想做的事情，比如:"
    Write-Host "    - '帮我搜索最新的 AI 新闻'"
    Write-Host "    - '用 git 创建一个新功能分支'"
    Write-Host "    - '查一下明天北京天气'"
    Write-Host ""
    Write-Host "【更多命令】" -ForegroundColor White
    Write-Host "  clawdbot --help          # 查看所有命令"
    Write-Host "  clawdbot skill list      # 查看已安装技能"
    Write-Host "  clawdbot config show     # 查看当前配置"

    # 常用命令速查表
    Write-Header "📋 常用命令速查"
    Write-Host "基础命令:" -ForegroundColor Cyan
    Write-Host "  clawdbot                 # 启动并对话"
    Write-Host "  clawdbot --version      # 查看版本"
    Write-Host "  clawdbot --help         # 帮助信息"
    Write-Host ""
    Write-Host "技能管理:" -ForegroundColor Cyan
    Write-Host "  clawdbot skill list              # 列出已安装技能"
    Write-Host "  clawdbot skill install <名称>    # 安装技能"
    Write-Host "  clawdbot skill uninstall <名称>  # 卸载技能"
    Write-Host ""
    Write-Host "配置管理:" -ForegroundColor Cyan
    Write-Host "  clawdbot config show     # 查看配置"
    Write-Host "  clawdbot config edit     # 编辑配置"
    Write-Host "  clawdbot config im qq   # 配置 IM 平台"
    Write-Host ""
    Write-Host "系统运维:" -ForegroundColor Cyan
    Write-Host "  clawdbot status         # 查看运行状态"
    Write-Host "  clawdbot logs           # 查看日志"
    Write-Host "  clawdbot restart       # 重启服务"
} else {
    Write-Host "⚠️ 未能在系统路径中检测到 'clawdbot' 指令。请检查网络或在 WSL 中手动运行尝试。" -ForegroundColor Yellow
}

