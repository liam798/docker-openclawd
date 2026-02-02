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

# 确保数据目录存在，并设置正确的权限（UID 1000:1000）
mkdir -p ./data/openclaw ./data/workspace ./data/openclaw/extensions 2>/dev/null || true
# 设置目录权限，确保容器内用户（1000:1000）可以读写
chmod -R 755 ./data/openclaw ./data/workspace 2>/dev/null || true
# 如果可能，设置所有者（需要 root 权限）
if [ "$(id -u)" = "0" ]; then
  chown -R 1000:1000 ./data/openclaw ./data/workspace 2>/dev/null || true
else
  # 非 root 用户：至少确保目录可写
  chmod -R 777 ./data/openclaw ./data/workspace 2>/dev/null || true
fi

# 读取 Gateway token（用于后续配置）
GATEWAY_TOKEN=$(grep '^OPENCLAW_GATEWAY_TOKEN=' .env 2>/dev/null | cut -d'=' -f2- | tr -d '"' || echo "")

# 检测并转换宿主机代理地址（容器内可访问）
# 如果宿主机有代理配置，将 127.0.0.1 转换为容器可访问的地址
detect_container_proxy() {
  local host_proxy="${HTTP_PROXY:-${http_proxy:-}}"
  if [ -z "$host_proxy" ]; then
    # 从 .env 读取
    host_proxy=$(grep '^HTTP_PROXY=' .env 2>/dev/null | cut -d'=' -f2- | tr -d '"' || echo "")
  fi
  
  if [ -n "$host_proxy" ] && echo "$host_proxy" | grep -q "127.0.0.1\|localhost"; then
    # 检测操作系统类型
    if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
      # macOS/Windows: 使用 host.docker.internal
      echo "$host_proxy" | sed 's|127.0.0.1|host.docker.internal|g' | sed 's|localhost|host.docker.internal|g'
    else
      # Linux: 尝试检测 Docker 网关 IP（默认 172.17.0.1）
      # 如果无法访问，回退到 host.docker.internal（Docker 20.10+ 支持）
      echo "$host_proxy" | sed 's|127.0.0.1|host.docker.internal|g' | sed 's|localhost|host.docker.internal|g'
    fi
  else
    # 如果代理地址不是 127.0.0.1，直接使用
    echo "$host_proxy"
  fi
}

CONTAINER_HTTP_PROXY=$(detect_container_proxy)
CONTAINER_HTTPS_PROXY="${CONTAINER_HTTP_PROXY}"

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
# 如果检测到宿主机代理，使用转换后的地址（容器可访问）；否则不使用代理
echo "[docker-setup] 检查并安装飞书插件..."
PROXY_ENV=""
if [ -n "$CONTAINER_HTTP_PROXY" ]; then
  PROXY_ENV="-e HTTP_PROXY=${CONTAINER_HTTP_PROXY} -e HTTPS_PROXY=${CONTAINER_HTTPS_PROXY} -e http_proxy=${CONTAINER_HTTP_PROXY} -e https_proxy=${CONTAINER_HTTPS_PROXY} -e NO_PROXY=localhost,127.0.0.1,::1 -e no_proxy=localhost,127.0.0.1,::1"
  echo "[docker-setup] 检测到代理配置，使用容器可访问的代理地址: ${CONTAINER_HTTP_PROXY}"
else
  PROXY_ENV="-e HTTP_PROXY= -e HTTPS_PROXY= -e http_proxy= -e https_proxy= -e NO_PROXY=* -e no_proxy=*"
fi

if docker compose run --rm ${PROXY_ENV} openclaw-cli plugins list 2>/dev/null | grep -q "feishu"; then
  echo "[docker-setup] 飞书插件已安装"
else
  echo "[docker-setup] 正在安装飞书插件 @m1heng-clawd/feishu ..."
  if docker compose run --rm ${PROXY_ENV} openclaw-cli plugins install @m1heng-clawd/feishu 2>/dev/null; then
    echo "[docker-setup] 飞书插件安装成功"
  else
    echo "[docker-setup] 警告: 飞书插件安装失败，可稍后手动安装:"
    if [ -n "$CONTAINER_HTTP_PROXY" ]; then
      echo "  HTTP_PROXY=${CONTAINER_HTTP_PROXY} HTTPS_PROXY=${CONTAINER_HTTPS_PROXY} docker compose run --rm openclaw-cli plugins install @m1heng-clawd/feishu"
    else
      echo "  docker compose run --rm openclaw-cli plugins install @m1heng-clawd/feishu"
    fi
  fi
fi

# 自动执行 onboarding（若配置不存在）
CONFIG_FILE="./data/openclaw/openclaw.json"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "[docker-setup] 检测到首次运行，执行自动配置（onboarding）..."
  
  # 等待 Gateway 完全就绪
  echo "[docker-setup] 等待 Gateway 完全就绪..."
  for i in {1..30}; do
    if docker compose exec openclaw-gateway node dist/index.js health --token "${GATEWAY_TOKEN:-}" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  
  # 创建最小配置文件（确保 Gateway 能启动）
  # 使用 gateway.auth.token（新格式），避免废弃警告
  echo "[docker-setup] 创建最小配置文件..."
  mkdir -p ./data/openclaw
  if [ -n "$GATEWAY_TOKEN" ]; then
    cat > "$CONFIG_FILE" <<EOF
{
  "gateway": {
    "auth": {
      "token": "${GATEWAY_TOKEN}"
    }
  }
}
EOF
  else
    cat > "$CONFIG_FILE" <<EOF
{
  "gateway": {
    "auth": {}
  }
}
EOF
  fi
  
  # 如果有 token，通过 CLI 设置（使用新格式）
  if [ -n "$GATEWAY_TOKEN" ]; then
    echo "[docker-setup] 设置 Gateway token..."
    docker compose run --rm ${PROXY_ENV} openclaw-cli config set gateway.auth.token "${GATEWAY_TOKEN}" 2>/dev/null || true
  fi
  
  # 尝试运行 onboard（非交互式可能不支持，但尝试一下）
  echo "[docker-setup] 运行 onboarding 配置向导（可能需要交互）..."
  echo "[docker-setup] 提示: 如果出现交互提示，可按 Ctrl+C 跳过，稍后手动执行: docker compose run --rm openclaw-cli onboard"
  
  # 使用 timeout 和 yes/no pipe 尝试非交互式运行
  # 如果 onboard 需要交互，这里会失败，但不影响 Gateway 启动
  timeout 30 docker compose run --rm -e OPENCLAW_GATEWAY_TOKEN="${GATEWAY_TOKEN}" openclaw-cli onboard 2>/dev/null || {
    echo "[docker-setup] Onboarding 可能需要交互式输入，已跳过"
    echo "[docker-setup] Gateway 已使用最小配置启动，可通过 Control UI 或 CLI 完善配置"
  }
else
  echo "[docker-setup] 检测到已有配置文件，跳过 onboarding"
  
  # 自动迁移旧配置格式（gateway.token -> gateway.auth.token）
  NEED_MIGRATION=false
  if [ -f "$CONFIG_FILE" ]; then
    # 检查是否存在旧格式的 gateway.token
    if python3 -c "
import json
import pathlib
import sys
p = pathlib.Path('$CONFIG_FILE')
try:
    data = json.loads(p.read_text())
    if 'gateway' in data and 'token' in data['gateway'] and 'auth' not in data['gateway']:
        sys.exit(0)  # 需要迁移
    sys.exit(1)  # 不需要迁移
except:
    sys.exit(1)
" 2>/dev/null; then
      NEED_MIGRATION=true
    fi
  fi
  
  if [ "$NEED_MIGRATION" = true ]; then
    echo "[docker-setup] 检测到旧配置格式，自动迁移 gateway.token -> gateway.auth.token ..."
    # 使用 Python 迁移配置
    python3 -c "
import json
import pathlib

p = pathlib.Path('$CONFIG_FILE')
try:
    data = json.loads(p.read_text())
    if 'gateway' in data and 'token' in data['gateway']:
        token = data['gateway']['token']
        if token:
            data.setdefault('gateway', {}).setdefault('auth', {})['token'] = token
            data['gateway'].pop('token', None)
            p.write_text(json.dumps(data, ensure_ascii=False, indent=2))
            print('配置已迁移')
except Exception as e:
    pass
" 2>/dev/null || true
    
    # 迁移后重启 Gateway 使新配置生效
    echo "[docker-setup] 重启 Gateway 使新配置生效..."
    docker compose restart openclaw-gateway >/dev/null 2>&1 || true
    sleep 3
  fi
fi

echo ""
echo "✅ Gateway 已启动并配置完成！"
echo "  - Control UI: http://127.0.0.1:18789/"
if [ -n "$GATEWAY_TOKEN" ]; then
  echo "  - Gateway Token: ${GATEWAY_TOKEN}"
  echo "  - 请在 Control UI 设置中填入该令牌"
fi
echo ""
echo "后续配置："
echo "  - 配置飞书通道: docker compose run --rm openclaw-cli config set channels.feishu.appId \"YOUR_APP_ID\""
echo "  - 查看日志: docker compose logs -f openclaw-gateway"
echo "  - 完整配置向导: docker compose run --rm openclaw-cli onboard"
