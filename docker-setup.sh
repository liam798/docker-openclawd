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

echo "[docker-setup] 构建镜像（首次较慢）..."
docker compose build

echo "[docker-setup] 启动 Gateway..."
docker compose up -d openclaw-gateway

echo ""
echo "Gateway 已启动。"
echo "  - Control UI: http://127.0.0.1:18789/"
echo "  - 若设置了 OPENCLAW_GATEWAY_TOKEN，请在 Control UI 设置中填入该令牌。"
echo ""
echo "首次使用建议执行: docker compose run --rm openclaw-cli onboard"
echo "查看日志: docker compose logs -f openclaw-gateway"
