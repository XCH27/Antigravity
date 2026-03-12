# OpenClaw-Skill-Project/scripts/uninstall.ps1

# 颜色变量定义
$Cyan = "Cyan"
$Yellow = "Yellow"
$Green = "Green"
$Gray = "Gray"

function Write-Header {
    param($text)
    Write-Host "`n=== $text ===" -ForegroundColor $Cyan
}

# 1. 检测安装模式 (Docker vs 原生)
Write-Header "读取系统安装记忆"
$wslConfigDir = "~/.config/clawdbot"
$installLogPath = "$wslConfigDir/install_report.json"
$logCheck = wsl -e bash -c "cat $installLogPath 2>/dev/null"

if ($logCheck -match '"Mode":\s*"1"') {
    Write-Host "检测到您之前使用的是 Docker 部署模式，正在通过 Docker 清理容器..." -ForegroundColor $Yellow
    wsl -e bash -c "cd ~/openclaw-docker && docker compose down -v 2>/dev/null || docker stop clawdbot 2>/dev/null && docker rm clawdbot 2>/dev/null"
    wsl -e bash -c "docker rmi justlovemaki/openclaw:latest 2>/dev/null || true"
}

# 2. 停止进程
Write-Header "正在停止原生 OpenClaw 进程"
wsl -e bash -c "pkill -f clawdbot || true"
Write-Host "原生进程已尝试终止。"

# 3. 清理文件
Write-Header "清理本地文件与配置"
Write-Host "正在移除 WSL 内的配置文件..."
wsl -e bash -c "rm -rf ~/.config/clawdbot"
wsl -e bash -c "rm -rf ~/.openclaw"

Write-Host "正在移除二进制文件..."
wsl -e bash -c "sudo rm /usr/local/bin/clawdbot 2>/dev/null || true"
wsl -e bash -c "rm -rf ~/openclaw-docker 2>/dev/null || true"

# 4. 安全引导清单 (账号解绑与 API 管理)
Write-Header "安全清理建议 (必须手动完成)"
Write-Host "为了您的账户安全，建议前往以下平台管理 API Key 或解绑 Bot：" -ForegroundColor $Yellow

Write-Host "`n--- 国内平台 ---" -ForegroundColor $Gray
Write-Host "Kimi:      https://platform.moonshot.cn/console/api-keys"
Write-Host "Minimax:   https://platform.minimaxi.com/user-center/basic-information"
Write-Host "智谱:      https://bigmodel.cn/usercenter/proj-mgmt/apikeys"

Write-Host "`n--- 国外平台 ---" -ForegroundColor $Gray
Write-Host "Google/Gemini: https://aistudio.google.com/api-keys"
Write-Host "Claude:        https://platform.claude.com/settings/keys"
Write-Host "ChatGPT:       https://platform.openai.com/"

Write-Host "`n--- Bot 管理 ---" -ForegroundColor $Gray
Write-Host "Telegram:  https://t.me/botfather (使用 /revoke 或 /deletebot)"
Write-Host "Discord:   https://discord.com/developers/applications"
Write-Host "GitHub:    https://github.com/settings/tokens"

Write-Host "`nOpenClaw 卸载完成。" -ForegroundColor $Green

