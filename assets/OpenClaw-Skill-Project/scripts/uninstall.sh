#!/bin/bash
# OpenClaw-Skill-Project/scripts/uninstall.sh

CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}=== 读取系统安装记忆 ===${NC}"
INSTALL_LOG=~/.config/clawdbot/install_report.json

# 判断安装模式
INSTALL_MODE=""
if [ -f "$INSTALL_LOG" ]; then
    if command -v jq &> /dev/null; then
        INSTALL_MODE=$(jq -r .Mode "$INSTALL_LOG" 2>/dev/null)
    else
        # Fallback to grep
        if grep -q '"Mode":\s*"1"' "$INSTALL_LOG"; then
            INSTALL_MODE="1"
        elif grep -q '"Mode":\s*"2"' "$INSTALL_LOG"; then
            INSTALL_MODE="2"
        fi
    fi
fi

# 根据模式清理
if [ "$INSTALL_MODE" == "1" ]; then
    echo -e "${YELLOW}检测到您之前使用的是 Docker 部署模式，正在通过 Docker 清理容器...${NC}"
    (cd ~/openclaw-docker && docker compose down -v 2>/dev/null) || (docker stop clawdbot 2>/dev/null && docker rm clawdbot 2>/dev/null)
    docker rmi justlovemaki/openclaw:latest 2>/dev/null || true
elif [ "$INSTALL_MODE" == "2" ]; then
    echo -e "${YELLOW}检测到您之前使用的是原生部署模式...${NC}"
else
    echo -e "${YELLOW}未找到安装记录，将清理所有可能的安装...${NC}"
fi

echo -e "${CYAN}=== 正在停止原生 OpenClaw 进程 ===${NC}"
pkill -f clawdbot || true

echo -e "${CYAN}=== 正在清理配置文件 ===${NC}"
rm -rf ~/.config/clawdbot
rm -rf ~/.openclaw

echo -e "${CYAN}=== 正在移除二进制文件 ===${NC}"
sudo rm /usr/local/bin/clawdbot 2>/dev/null || true
rm -rf ~/openclaw-docker 2>/dev/null || true

echo -e "${GREEN}OpenClaw 卸载完成。${NC}"
# 后续会自动由 AI 接管输出账号解绑链接

