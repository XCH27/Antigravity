#!/bin/bash
# OpenClaw-Skill-Project/scripts/install.sh

# 颜色定义
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

write_header() {
    echo -e "\n${CYAN}=== $1 ===${NC}"
}

echo -e "${NC}官方网站: https://openclaw.ai/"
echo -e "官方 GitHub: https://github.com/openclaw/openclaw"

# 1. 系统与硬件环境识别
OS_TYPE=$(uname)
write_header "系统预检: $OS_TYPE"

if [ "$OS_TYPE" == "Darwin" ]; then
    echo "检测到 macOS 系统，正在验证硬件要求..."
    
    # 硬件检查: CPU
    CPU_INFO=$(sysctl -n machdep.cpu.brand_string)
    if [[ "$CPU_INFO" == *"Apple M"* ]] || [[ "$CPU_INFO" == *"Intel(R) Core(TM) i5"* ]] || [[ "$CPU_INFO" == *"Intel(R) Core(TM) i7"* ]] || [[ "$CPU_INFO" == *"Intel(R) Core(TM) i9"* ]]; then
        echo -e "${GREEN}[OK] CPU: $CPU_INFO${NC}"
    else
        echo -e "${RED}[FAIL] CPU 要求 M 系列芯片或 Intel i5 以上。当前: $CPU_INFO${NC}"
        exit 1
    fi

    # 硬件检查: 内存 (8GB+)
    MEM_BYTES=$(sysctl -n hw.memsize)
    MEM_GB=$((MEM_BYTES / 1024 / 1024 / 1024))
    if [ "$MEM_GB" -ge 8 ]; then
        echo -e "${GREEN}[OK] 内存: ${MEM_GB}GB${NC}"
    else
        echo -e "${RED}[FAIL] 内存要求 8GB 以上。当前: ${MEM_GB}GB${NC}"
        exit 1
    fi

    # 硬件检查: 磁盘空间 (10GB+)
    FREE_SPACE=$(df -g / | awk 'NR==2 {print $4}')
    if [ "$FREE_SPACE" -ge 10 ]; then
        echo -e "${GREEN}[OK] 磁盘空间: 剩余 ${FREE_SPACE}GB${NC}"
    else
        echo -e "${RED}[FAIL] 磁盘空间要求 10GB 以上空闲。当前: ${FREE_SPACE}GB${NC}"
        exit 1
    fi

    # 系统版本检查: macOS 12+
    OS_VER=$(sw_vers -productVersion)
    OS_MAJOR=$(echo $OS_VER | cut -d. -f1)
    if [ "$OS_MAJOR" -ge 12 ]; then
        echo -e "${GREEN}[OK] macOS 版本: $OS_VER${NC}"
    else
        echo -e "${RED}[FAIL] 系统版本要求 macOS 12 Monterey 或更高。当前: $OS_VER${NC}"
        exit 1
    fi

    # 依赖自动安装流
    write_header "正在配置前置软件"
    
    # 1. Homebrew
    if ! command -v brew &> /dev/null; then
        echo "正在安装 Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
        echo -e "${GREEN}[OK] Homebrew 已安装${NC}"
    fi

    # 2. Node.js 22+
    NODE_NEEDED=22
    if ! command -v node &> /dev/null || [ "$(node -v | cut -d. -f1 | tr -d 'v')" -lt "$NODE_NEEDED" ]; then
        echo "正在通过 Homebrew 安装/更新 Node.js 22+..."
        brew install node@22
        brew link --overwrite node@22
    else
        echo -e "${GREEN}[OK] Node.js $(node -v) 已就绪${NC}"
    fi

elif [ "$OS_TYPE" == "Linux" ]; then
    echo "检测到 Linux 系统，正在验证硬件要求..."

    # 硬件检查: 内存 (8GB+)
    MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    MEM_GB=$((MEM_KB / 1024 / 1024))
    if [ "$MEM_GB" -ge 8 ]; then
        echo -e "${GREEN}[OK] 内存: ${MEM_GB}GB${NC}"
    else
        echo -e "${RED}[FAIL] 内存要求 8GB 以上。当前: ${MEM_GB}GB${NC}"
        exit 1
    fi

    # 硬件检查: 磁盘空间 (10GB+)
    FREE_SPACE=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    if [ "$FREE_SPACE" -ge 10 ]; then
        echo -e "${GREEN}[OK] 磁盘空间: 剩余 ${FREE_SPACE}GB${NC}"
    else
        echo -e "${RED}[FAIL] 磁盘空间要求 10GB 以上空闲。当前: ${FREE_SPACE}GB${NC}"
        exit 1
    fi

    # 依赖检查与安装
    write_header "正在配置前置软件"

    # 1. Node.js 22+
    NODE_NEEDED=22
    if ! command -v node &> /dev/null || [ "$(node -v | cut -d. -f1 | tr -d 'v')" -lt "$NODE_NEEDED" ]; then
        echo "正在安装 Node.js 22+..."
        if command -v apt-get &> /dev/null; then
            curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
            sudo apt-get install -y nodejs
        elif command -v yum &> /dev/null; then
            curl -fsSL https://rpm.nodesource.com/setup_22.x | sudo bash -
            sudo yum install -y nodejs
        fi
    else
        echo -e "${GREEN}[OK] Node.js $(node -v) 已就绪${NC}"
    fi

    # 2. Docker (可选)
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}[提示] Docker 未安装，如需 Docker 模式请稍后手动安装${NC}"
    else
        echo -e "${GREEN}[OK] Docker 已就绪${NC}"
    fi
else
    echo -e "${RED}错误: 不支持的操作系统流。${NC}"
    exit 1
fi

# 2. 运行环境与部署模式选择
write_header "运行环境选择"
echo -e "${YELLOW}OpenClaw 建议在隔离环境（如 Docker）中运行以获得最佳的系统安全性。${NC}"
echo -e "请选择您的安装方案:"

echo -e "\n${GREEN}[方案 1: 隔离环境 - 推荐]${NC}"
echo "Docker 容器安装 (进程与文件系统完全沙盒化，预装国内 IM，最安全)"

echo -e "\n${YELLOW}[方案 2: 宿主系统原生]${NC}"
echo "原生安装 (直接运行在当前 macOS/Linux 系统中，配置简单但隔离度较低)"

echo -e "\n${NC}[方案 3: 远程云端]"
echo "云端 VPS 资源指引 (完全脱离本机运行)"

read -p "请选择模式 (1/2/3): " mode

if [ "$mode" == "1" ]; then
    # Docker 容器安装 (隔离环境 - 推荐)
    write_header "Docker 部署指引"
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}未检测到 Docker，请先安装 Docker。${NC}"
        exit 1
    fi
    echo "参考项目: https://github.com/justlovemaki/OpenClaw-Docker-CN-IM"
    echo "正在为您尝试自动拉取编排文件并启动容器..."
    mkdir -p ~/openclaw-docker && cd ~/openclaw-docker
    curl -fsSL -O https://raw.githubusercontent.com/justlovemaki/OpenClaw-Docker-CN-IM/main/docker-compose.yml
    if command -v docker-compose &> /dev/null; then
        docker-compose up -d
    else
        docker compose up -d
    fi
elif [ "$mode" == "2" ]; then
    # 原生安装 (宿主系统)
    write_header "执行原生安装"
    curl -fsSL https://openclaw.ai/install.sh | bash
elif [ "$mode" == "3" ]; then
    write_header "云端资源"
    echo "火山引擎: https://www.volcengine.com/docs/6462/1161048"
    echo "腾讯云: https://cloud.tencent.com/developer/article/2624973"
    exit 0
fi

# 3. 安全配置引导
write_header "安全配置引导"
echo -e "${YELLOW}!!! 密钥安全提醒: 严禁在任何公共日志或不安全的命令行历史中明文传递 API Key。${NC}"
echo "建议将您的 API_KEY 写入 ~/.config/clawdbot/config.json 并设置权限 (chmod 600)。"

# 4. API 配置交互式向导
write_header "API 配置向导"
echo -e "OpenClaw 需要配置 LLM API 才能正常工作。"
echo -e "${CYAN}请选择您的 API 提供商:${NC}"
echo ""
echo -e "${GREEN}[国内 API - 网络稳定]${NC}"
echo "  1. Kimi (月之暗面)     - https://platform.moonshot.cn/"
echo "  2. 智谱 AI (Zhipu)     - https://bigmodel.cn/"
echo "  3. MiniMax (稀宇)     - https://platform.minimaxi.com/"
echo ""
echo -e "${YELLOW}[国外 API - 能力更强]${NC}"
echo "  4. Claude (Anthropic)  - https://platform.claude.com/"
echo "  5. OpenAI (ChatGPT)   - https://platform.openai.com/"
echo "  6. Google Gemini      - https://aistudio.google.com/"
echo ""
echo "  7. 暂不配置 (稍后手动配置)"

read -p "请选择 (1-7): " api_choice

case $api_choice in
    1)  # Kimi
        echo ""
        echo -e "${GREEN}=== Kimi API 配置指南 ===${NC}"
        echo "1. 访问 https://platform.moonshot.cn/ 注册/登录"
        echo "2. 进入「API 密钥管理」创建新密钥"
        echo "3. 复制密钥并妥善保存（只显示一次）"
        echo ""
        echo -e "模型推荐: ${CYAN}moonshot-v1-8k${NC}"
        api_config="KIMI"
        ;;
    2)  # 智谱
        echo ""
        echo -e "${GREEN}=== 智谱 AI API 配置指南 ===${NC}"
        echo "1. 访问 https://bigmodel.cn/ 注册/登录"
        echo "2. 进入「API 密钥」创建新密钥"
        echo "3. 复制密钥并妥善保存"
        echo ""
        echo -e "模型推荐: ${CYAN}glm-4${NC}"
        api_config="ZHIPU"
        ;;
    3)  # MiniMax
        echo ""
        echo -e "${GREEN}=== MiniMax API 配置指南 ===${NC}"
        echo "1. 访问 https://platform.minimaxi.com/ 注册/登录"
        echo "2. 进入「开发者后台」创建 API Key"
        echo "3. 复制密钥并妥善保存"
        echo ""
        echo -e "模型推荐: ${CYAN}abab6.5s-chat${NC}"
        api_config="MINIMAX"
        ;;
    4)  # Claude
        echo ""
        echo -e "${GREEN}=== Claude API 配置指南 ===${NC}"
        echo "1. 访问 https://platform.claude.com/ 注册/登录"
        echo "2. 进入「Settings」→「API Keys」创建密钥"
        echo "3. 复制密钥并妥善保存"
        echo ""
        echo -e "模型推荐: ${CYAN}claude-3-5-sonnet-20241022${NC}"
        api_config="CLAUDE"
        ;;
    5)  # OpenAI
        echo ""
        echo -e "${GREEN}=== OpenAI API 配置指南 ===${NC}"
        echo "1. 访问 https://platform.openai.com/ 注册/登录"
        echo "2. 进入「API Keys」创建新密钥"
        echo "3. 复制密钥并妥善保存"
        echo ""
        echo -e "模型推荐: ${CYAN}gpt-4o${NC}"
        api_config="OPENAI"
        ;;
    6)  # Gemini
        echo ""
        echo -e "${GREEN}=== Google Gemini API 配置指南 ===${NC}"
        echo "1. 访问 https://aistudio.google.com/app/apikey"
        echo "2. 创建新 API 密钥"
        echo "3. 复制密钥并妥善保存"
        echo ""
        echo -e "模型推荐: ${CYAN}gemini-1.5-pro${NC}"
        api_config="GEMINI"
        ;;
    7)  # 跳过
        echo -e "${YELLOW}已跳过 API 配置，稍后可运行 'clawdbot config api' 重新配置${NC}"
        api_config="SKIP"
        ;;
    *)
        echo -e "${YELLOW}无效选择，已跳过 API 配置${NC}"
        api_config="SKIP"
        ;;
esac

if [ "$api_config" != "SKIP" ] && [ "$api_config" != "" ]; then
    echo ""
    echo -e "${CYAN}配置方法:${NC}"
    echo "  clawdbot config api $api_config"
    echo ""
    echo -e "${GRAY}或手动写入配置文件: ~/.config/clawdbot/config.json${NC}"
fi

# 生成智能安装记录
mkdir -p ~/.config/clawdbot
cat <<EOF > ~/.config/clawdbot/install_report.json
{
  "InstallDate": "$(date '+%Y-%m-%d %H:%M:%S')",
  "Mode": "$mode",
  "OS": "$(uname)",
  "ApiProvider": "$api_config",
  "Services": ["OpenClaw Core", "Node.js Environment"]
}
EOF

echo -e "${GREEN}脚本执行完毕。安装记录已存至 ~/.config/clawdbot/install_report.json${NC}"

# 验证安装状态
write_header "验证安装状态"
if [ "$mode" == "2" ]; then
    # 原生安装验证
    if command -v clawdbot &> /dev/null; then
        VER=$(clawdbot --version 2>/dev/null)
        echo -e "${GREEN}[成功] 原生版本检测正常 (版本: $VER)。${NC}"
    else
        echo -e "${YELLOW}[警告] 未能在 PATH 中找到 clawdbot。可能当前终端未生效或环境变量存在问题。${NC}"
    fi
elif [ "$mode" == "1" ]; then
    # Docker 安装验证
    DOCKER_STATUS=$(docker ps --filter "name=clawdbot" --format "{{.Status}}" 2>/dev/null)
    if [[ "$DOCKER_STATUS" == *"Up"* ]]; then
        echo -e "${GREEN}[成功] Docker 容器运行正常，状态: $DOCKER_STATUS。${NC}"
    else
        echo -e "${YELLOW}[警告] Docker 容器可能未成功启动，请运行 'docker logs clawdbot' 查看详情。${NC}"
    fi
fi

# 4. 自动安装必备技能 (仅原生安装模式)
if [ "$mode" == "2" ] && command -v clawdbot &> /dev/null; then
    write_header "正在安装必备技能"
    echo -e "${YELLOW}根据 SKILL.md 规范，自动安装必备技能...${NC}"

    # 必备技能列表
    CORE_SKILLS=(
        "self-improving-agent"
        "tavily-search"
        "GitHub"
        "weather"
        "find-skills"
        "proactive-agent"
    )

    for skill in "${CORE_SKILLS[@]}"; do
        echo -n "安装 $skill ... "
        if clawdbot skill install "$skill" 2>/dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${YELLOW}跳过${NC}"
        fi
    done

    echo -e "${GREEN}必备技能安装完成！${NC}"
fi

# 5. Web UI 可选安装 (仅原生模式)
if [ "$mode" == "2" ] && command -v clawdbot &> /dev/null; then
    write_header "Web UI 图形界面 (可选)"
    echo -e "OpenClaw 支持以下 Web UI 方案："
    echo ""
    echo -e "${CYAN}[1]${NC} 安装 Web Dashboard (社区版)"
    echo "    命令: clawdbot skill install openclaw/web-dashboard"
    echo ""
    echo -e "${CYAN}[2]${NC} 启动内置 Web 服务 (如支持)"
    echo "    命令: clawdbot web"
    echo ""
    echo -e "${CYAN}[3]${NC} 跳过 (默认)"
    echo ""
    read -p "请选择是否安装 Web UI (1/2/3): " webui_choice

    if [ "$webui_choice" == "1" ]; then
        echo -e "正在安装 Web Dashboard..."
        clawdbot skill install openclaw/web-dashboard 2>/dev/null || echo -e "${YELLOW}未找到该技能，请尝试其他方案${NC}"
    elif [ "$webui_choice" == "2" ]; then
        echo -e "尝试启动内置 Web 服务..."
        clawdbot web --help 2>/dev/null || echo -e "${YELLOW}内置 Web 服务不可用${NC}"
    fi
fi

# 6. IM 绑定交互式向导 (仅原生模式)
if [ "$mode" == "2" ] && command -v clawdbot &> /dev/null; then
    write_header "即时通讯 (IM) 绑定向导"
    echo -e "${YELLOW}将 OpenClaw 连接到 IM 平台，即可通过微信/QQ/钉钉等与它对话${NC}"
    echo ""
    echo -e "${CYAN}请选择要绑定的平台:${NC}"
    echo "  1. QQ        (国内最常用)"
    echo "  2. 飞书      (字节跳动)"
    echo "  3. 钉钉      (阿里系)"
    echo "  4. 企业微信  (腾讯系)"
    echo "  5. Telegram  (国际版)"
    echo "  6. Discord  (国际版)"
    echo "  7. 暂不绑定  (以后再说)"
    echo ""
    read -p "请选择 (1-7): " im_choice

    case $im_choice in
        1)  # QQ
            echo ""
            echo -e "${GREEN}=== QQ 绑定指南 ===${NC}"
            echo "1. 打开 https://q.qq.com/qqbot/openclaw/login.html"
            echo "2. 使用 QQ 扫码登录"
            echo "3. 创建或选择一个 OpenClaw Bot"
            echo "4. 获取 AppID 和 Token"
            echo ""
            echo "完成后，运行以下命令配置:"
            echo -e "${CYAN}  clawdbot config im qq${NC}"
            ;;
        2)  # 飞书
            echo ""
            echo -e "${GREEN}=== 飞书绑定指南 ===${NC}"
            echo "1. 打开 https://bytedance.larkoffice.com/docx/MFK7dDFLFoVlOGxWCv5cTXKmnMh"
            echo "2. 创建企业应用"
            echo "3. 添加机器人并获取 App ID 和 App Secret"
            echo "4. 配置事件订阅和权限"
            echo ""
            echo "完成后，运行以下命令配置:"
            echo -e "${CYAN}  clawdbot config im feishu${NC}"
            ;;
        3)  # 钉钉
            echo ""
            echo -e "${GREEN}=== 钉钉绑定指南 ===${NC}"
            echo "1. 打开 https://open.dingtalk.com/document/dingstart/build-dingtalk-ai-employees"
            echo "2. 创建企业内部开发应用"
            echo "3. 添加机器人并获取 AppKey 和 AppSecret"
            echo "4. 配置机器人权限"
            echo ""
            echo "完成后，运行以下命令配置:"
            echo -e "${CYAN}  clawdbot config im dingtalk${NC}"
            ;;
        4)  # 企业微信
            echo ""
            echo -e "${GREEN}=== 企业微信绑定指南 ===${NC}"
            echo "1. 打开 https://work.weixin.qq.com/nl/index/openclaw"
            echo "2. 创建企业微信应用"
            echo "3. 获取 CorpID 和 Secret"
            echo "4. 配置应用权限"
            echo ""
            echo "完成后，运行以下命令配置:"
            echo -e "${CYAN}  clawdbot config im wecom${NC}"
            ;;
        5)  # Telegram
            echo ""
            echo -e "${GREEN}=== Telegram 绑定指南 ===${NC}"
            echo "1. 打开 https://t.me/BotFather"
            echo "2. 发送 /newbot 创建新机器人"
            echo "3. 获取 Bot Token"
            echo "4. 与 @userinfobot 对话获取你的 User ID"
            echo ""
            echo "完成后，运行以下命令配置:"
            echo -e "${CYAN}  clawdbot config im telegram${NC}"
            ;;
        6)  # Discord
            echo ""
            echo -e "${GREEN}=== Discord 绑定指南 ===${NC}"
            echo "1. 打开 https://discord.com/developers/applications"
            echo "2. 创建新应用"
            echo "3. 添加 Bot 用户并获取 Token"
            echo "4. 配置 intents 权限"
            echo "5. 复制 Client ID 并邀请机器人到服务器"
            echo ""
            echo "完成后，运行以下命令配置:"
            echo -e "${CYAN}  clawdbot config im discord${NC}"
            ;;
        7)  # 跳过
            echo -e "${YELLOW}已跳过 IM 绑定，稍后可运行 'clawdbot config im' 重新配置${NC}"
            ;;
        *)
            echo -e "${YELLOW}无效选择，已跳过 IM 绑定${NC}"
            ;;
    esac

    if [ "$im_choice" != "7" ] && [ "$im_choice" != "" ]; then
        echo ""
        echo -e "${GREEN}配置完成后，重启 OpenClaw 即可生效:${NC}"
        echo "  clawdbot restart"
    fi
fi

# 7. 首次启动指南
write_header "🚀 首次启动指南"
echo -e "${GREEN}恭喜！OpenClaw 安装完成！${NC}"
echo ""
echo "【启动 OpenClaw】"
if [ "$mode" == "1" ]; then
    echo "  Docker 模式: cd ~/openclaw-docker && docker compose logs -f"
else
    echo "  原生模式: clawdbot"
fi
echo ""
echo "【开始对话】"
echo "  在终端直接输入你想做的事情，比如:"
echo "    - '帮我搜索最新的 AI 新闻'"
echo "    - '用 git 创建一个新功能分支'"
echo "    - '查一下明天北京天气'"
echo ""
echo "【更多命令】"
echo "  clawdbot --help          # 查看所有命令"
echo "  clawdbot skill list      # 查看已安装技能"
echo "  clawdbot config show     # 查看当前配置"

# 8. 常用命令速查表
write_header "📋 常用命令速查"
echo -e "${CYAN}基础命令:${NC}"
echo "  clawdbot                 # 启动并对话"
echo "  clawdbot --version      # 查看版本"
echo "  clawdbot --help         # 帮助信息"
echo ""
echo -e "${CYAN}技能管理:${NC}"
echo "  clawdbot skill list              # 列出已安装技能"
echo "  clawdbot skill install <名称>    # 安装技能"
echo "  clawdbot skill uninstall <名称>  # 卸载技能"
echo ""
echo -e "${CYAN}配置管理:${NC}"
echo "  clawdbot config show     # 查看配置"
echo "  clawdbot config edit     # 编辑配置"
echo "  clawdbot config im qq   # 配置 IM 平台"
echo ""
echo -e "${CYAN}系统运维:${NC}"
echo "  clawdbot status         # 查看运行状态"
echo "  clawdbot logs           # 查看日志"
echo "  clawdbot restart        # 重启服务"

# 9. 龙虾技能安装准备 (专业技能推荐)
write_header "龙虾技能商店推荐 (自定义您的 AI 助理)"
echo -e "环境配置已就绪，您可以根据您的领域选择以下必备技能:"

echo -e "\n${CYAN}[💻 研发/剪辑/股票]${NC}"
echo -e "- Project Summary      : 代码库分析"
echo -e "- ffmpeg-video-editor  : 自然语言剪视频"
echo -e "- Stock Analysis       : 股市大盘与组合监控"

echo -e "\n${CYAN}[📅 办公/协作]${NC}"
echo -e "- AI Meeting Notes     : 自动会议摘要"
echo -e "- GitHub               : 代码仓库协作"

echo -e "\n${YELLOW}[🌟 核心总管]${NC}"
echo -e "- self-improving-agent : 自修复核心"
echo -e "- tavily-search        : 全球联网搜索"

echo -e "\n${CYAN}[💬 IM 官方配置教程]${NC}"
echo -e "- QQ       : https://q.qq.com/qqbot/openclaw/login.html"
echo -e "- 企业微信 : https://work.weixin.qq.com/nl/index/openclaw"
echo -e "- 钉钉     : https://open.dingtalk.com/document/dingstart/build-dingtalk-ai-employees"
echo -e "- 飞书     : https://bytedance.larkoffice.com/docx/MFK7dDFLFoVlOGxWCv5cTXKmnMh"

echo -e "\n安装方法: 在终端运行 clawdbot skill install [作者]/[名称]"
echo -e "更多技能见: https://clawhub.ai/"

