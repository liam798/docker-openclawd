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
      # Linux: 检测 Docker 网关 IP
      local docker_gateway_ip="172.17.0.1"
      
      # 尝试从 docker network inspect 获取网关 IP
      if command -v docker >/dev/null 2>&1; then
        local gateway=$(docker network inspect bridge --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null | head -n1)
        if [ -n "$gateway" ] && [ "$gateway" != "<no value>" ]; then
          docker_gateway_ip="$gateway"
        else
          # 尝试从 ip route 获取
          local route_gateway=$(ip route show default 2>/dev/null | awk '/default/ {print $3}' | head -n1)
          if [ -n "$route_gateway" ]; then
            docker_gateway_ip="$route_gateway"
          fi
        fi
      fi
      
      # 将 127.0.0.1 替换为检测到的 Docker 网关 IP
      echo "$host_proxy" | sed "s|127.0.0.1|${docker_gateway_ip}|g" | sed "s|localhost|${docker_gateway_ip}|g"
    fi
  else
    # 如果代理地址不是 127.0.0.1，直接使用
    echo "$host_proxy"
  fi
}

CONTAINER_HTTP_PROXY=$(detect_container_proxy)
CONTAINER_HTTPS_PROXY="${CONTAINER_HTTP_PROXY}"

# 自动检测并写入运行时代理配置到 .env
if [ -n "$CONTAINER_HTTP_PROXY" ]; then
  echo "[docker-setup] 检测到代理配置: ${CONTAINER_HTTP_PROXY}"
  echo "[docker-setup] 自动配置运行时代理（已转换为容器可访问地址）..."
  
  # 更新或添加 OPENCLAW_RUNTIME_HTTP_PROXY
  if grep -q '^OPENCLAW_RUNTIME_HTTP_PROXY=' .env 2>/dev/null; then
    sed -i.bak "s|^OPENCLAW_RUNTIME_HTTP_PROXY=.*|OPENCLAW_RUNTIME_HTTP_PROXY=${CONTAINER_HTTP_PROXY}|" .env
  else
    echo "OPENCLAW_RUNTIME_HTTP_PROXY=${CONTAINER_HTTP_PROXY}" >> .env
  fi
  
  # 更新或添加 OPENCLAW_RUNTIME_HTTPS_PROXY
  if grep -q '^OPENCLAW_RUNTIME_HTTPS_PROXY=' .env 2>/dev/null; then
    sed -i.bak "s|^OPENCLAW_RUNTIME_HTTPS_PROXY=.*|OPENCLAW_RUNTIME_HTTPS_PROXY=${CONTAINER_HTTPS_PROXY}|" .env
  else
    echo "OPENCLAW_RUNTIME_HTTPS_PROXY=${CONTAINER_HTTPS_PROXY}" >> .env
  fi
  
  # 更新或添加 OPENCLAW_RUNTIME_ALL_PROXY
  if grep -q '^OPENCLAW_RUNTIME_ALL_PROXY=' .env 2>/dev/null; then
    sed -i.bak "s|^OPENCLAW_RUNTIME_ALL_PROXY=.*|OPENCLAW_RUNTIME_ALL_PROXY=${CONTAINER_HTTP_PROXY}|" .env
  else
    echo "OPENCLAW_RUNTIME_ALL_PROXY=${CONTAINER_HTTP_PROXY}" >> .env
  fi
  
  # 清理备份文件
  rm -f .env.bak 2>/dev/null || true
else
  echo "[docker-setup] 未检测到代理配置，将不使用代理运行"
  echo "[docker-setup] 提示: 如需配置代理，可在 .env 中设置 OPENCLAW_RUNTIME_HTTP_PROXY 等变量"
  
  # 确保运行时代理变量为空（如果存在则清空，不存在则添加空值）
  if grep -q '^OPENCLAW_RUNTIME_HTTP_PROXY=' .env 2>/dev/null; then
    sed -i.bak "s|^OPENCLAW_RUNTIME_HTTP_PROXY=.*|OPENCLAW_RUNTIME_HTTP_PROXY=|" .env
  else
    echo "OPENCLAW_RUNTIME_HTTP_PROXY=" >> .env
  fi
  
  if grep -q '^OPENCLAW_RUNTIME_HTTPS_PROXY=' .env 2>/dev/null; then
    sed -i.bak "s|^OPENCLAW_RUNTIME_HTTPS_PROXY=.*|OPENCLAW_RUNTIME_HTTPS_PROXY=|" .env
  else
    echo "OPENCLAW_RUNTIME_HTTPS_PROXY=" >> .env
  fi
  
  rm -f .env.bak 2>/dev/null || true
fi

# 使用 npm 安装 OpenClaw，无需克隆源码（镜像构建时 npm install -g openclaw）
echo "[docker-setup] 构建镜像（首次较慢，将从 npm 安装 OpenClaw）..."
docker compose build

echo "[docker-setup] 启动 Gateway..."
docker compose up -d openclaw-gateway

# 自动执行 onboarding（若配置不存在）
CONFIG_FILE="./data/openclaw/openclaw.json"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "[docker-setup] 检测到首次运行，执行自动配置（onboarding）..."
  
  # 等待 Gateway 完全就绪
  echo "[docker-setup] 等待 Gateway 完全就绪..."
  for i in {1..30}; do
    if docker compose exec openclaw-gateway openclaw health --token "${GATEWAY_TOKEN:-}" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  
  # 创建最小配置文件（确保 Gateway 能启动）
  # 使用 gateway.auth.token（新格式），避免废弃警告
  # 添加 gateway.mode=local 避免 Gateway 因缺少模式而反复重启
  echo "[docker-setup] 创建最小配置文件..."
  mkdir -p ./data/openclaw
  if [ -n "$GATEWAY_TOKEN" ]; then
    cat > "$CONFIG_FILE" <<EOF
{
  "gateway": {
    "mode": "local",
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
    "mode": "local",
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
  
  # 只在有交互终端时执行 onboarding，避免非交互环境卡住
  if [ -t 0 ] && [ -t 1 ]; then
    # 有交互终端：使用 -it 参数交互执行
    echo "[docker-setup] 检测到交互终端，启动配置向导（onboarding）..."
    echo "[docker-setup] 提示: 可按 Ctrl+C 跳过，稍后手动执行: docker compose run --rm -it openclaw-cli onboard"
    docker compose run --rm -it -e OPENCLAW_GATEWAY_TOKEN="${GATEWAY_TOKEN}" ${PROXY_ENV} openclaw-cli onboard || {
      echo "[docker-setup] Onboarding 已取消或失败"
      echo "[docker-setup] Gateway 已使用最小配置启动，可通过 Control UI 或 CLI 完善配置"
    }
  else
    # 非交互环境：跳过并提示
    echo "[docker-setup] 未检测到交互终端，跳过自动 onboarding"
    echo "[docker-setup] Gateway 已使用最小配置启动，请手动执行配置向导:"
    echo "  docker compose run --rm -it openclaw-cli onboard"
    echo "[docker-setup] 或通过 Control UI 进行配置: http://127.0.0.1:18789/"
  fi
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
