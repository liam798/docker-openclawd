#!/usr/bin/env bash
# OpenClaw Docker 一键设置与启动
# 用法: ./docker-setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 若没有 .env，从示例复制
if [ ! -f .env ]; then
  cp .env.example .env
  echo "[docker-setup] 已创建 .env（可从 .env.example 修改）"
fi

# 若 .env 中 OPENCLAW_GATEWAY_TOKEN 为空，生成一个并写回
if ! grep -q '^OPENCLAW_GATEWAY_TOKEN=.\+' .env 2>/dev/null; then
  TOKEN=$(openssl rand -hex 24 2>/dev/null || echo "")
  if [ -n "$TOKEN" ]; then
    if grep -q '^OPENCLAW_GATEWAY_TOKEN=' .env; then
      sed -i.bak "s/^OPENCLAW_GATEWAY_TOKEN=.*/OPENCLAW_GATEWAY_TOKEN=$TOKEN/" .env
    else
      echo "OPENCLAW_GATEWAY_TOKEN=$TOKEN" >> .env
    fi
    echo "[docker-setup] 已生成 OPENCLAW_GATEWAY_TOKEN 并写入 .env"
  fi
fi

# 确保数据目录存在
mkdir -p ./data/openclaw ./data/workspace 2>/dev/null || true

# 若 openclaw-src/ 不存在则自动克隆（构建时 COPY 进镜像）
if [ ! -d "openclaw-src/.git" ]; then
  echo "[docker-setup] 正在克隆 openclaw/openclaw 到 openclaw-src/ ..."
  git clone --depth 1 https://github.com/openclaw/openclaw.git openclaw-src
fi

echo "[docker-setup] 构建镜像（首次较慢）..."
docker compose build

echo "[docker-setup] 启动 Gateway..."
docker compose up -d openclaw-gateway

# 等待 Gateway 启动并自动安装飞书插件
echo "[docker-setup] 等待 Gateway 就绪并安装飞书插件..."
sleep 8

# 自动安装飞书插件（若未安装）
echo "[docker-setup] 检查并安装飞书插件..."
if docker compose run --rm openclaw-cli plugins list 2>/dev/null | grep -q "feishu"; then
  echo "[docker-setup] 飞书插件已安装"
else
  echo "[docker-setup] 正在安装飞书插件 @m1heng-clawd/feishu ..."
  if docker compose run --rm openclaw-cli plugins install @m1heng-clawd/feishu 2>/dev/null; then
    echo "[docker-setup] 飞书插件安装成功"
  else
    echo "[docker-setup] 警告: 飞书插件安装失败，可稍后手动安装:"
    echo "  docker compose run --rm openclaw-cli plugins install @m1heng-clawd/feishu"
  fi
fi

echo ""
echo "Gateway 已启动。"
echo "  - Control UI: http://127.0.0.1:18789/"
echo "  - 若设置了 OPENCLAW_GATEWAY_TOKEN，请在 Control UI 设置中填入该令牌。"
echo ""
echo "首次使用建议执行: docker compose run --rm openclaw-cli onboard"
echo "配置飞书通道: docker compose run --rm openclaw-cli config set channels.feishu.appId \"YOUR_APP_ID\""
echo "查看日志: docker compose logs -f openclaw-gateway"
