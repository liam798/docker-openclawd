# docker-openclawd

OpenClawd 的 Docker 部署方案，用于在容器中运行 Gateway 与 CLI，无需在宿主机安装 Node 或全局包。

- **OpenClaw**：自托管个人 AI 助手，支持 WhatsApp / Telegram / Discord / Slack 等通道，对接 Pi 等 Agent。  
- **文档**：[docs.clawd.bot](https://docs.clawd.bot/) · [GitHub openclaw/openclaw](https://github.com/openclaw/openclaw)

## 前置要求

- Docker Desktop 或 Docker Engine + Docker Compose v2
- 宿主机可访问 GitHub（构建时会克隆 openclaw/openclaw）

## 快速开始

**方式一：一键脚本（推荐）**

```bash
git clone https://github.com/liam798/docker-openclawd.git
cd docker-openclawd
./docker-setup.sh
```

脚本会创建 `.env`、生成 Gateway 令牌、构建镜像并启动 Gateway。

**方式二：手动步骤**

```bash
# 1. 克隆本仓库
git clone https://github.com/liam798/docker-openclawd.git
cd docker-openclawd

# 2. 复制环境变量并（可选）编辑
cp .env.example .env
# 建议生成并填写 OPENCLAW_GATEWAY_TOKEN，例如: openssl rand -hex 24

# 3. 构建并启动 Gateway
docker compose build
docker compose up -d openclaw-gateway
```

启动后：

- **Control UI（仪表盘）**：浏览器打开 `http://127.0.0.1:18789/`（或宿主机 IP:18789）
- 若设置了 `OPENCLAW_GATEWAY_TOKEN`，在 Control UI 的「设置 → token」中填入该令牌

配置与工作区会持久化在 `./data/openclaw` 与 `./data/workspace`（可在 `.env` 中修改 `OPENCLAW_CONFIG_DIR` / `OPENCLAW_WORKSPACE_DIR`）。

## 首次配置（Onboarding）

建议先跑一次引导，生成基础配置与 Gateway 令牌：

```bash
docker compose run --rm openclaw-cli onboard
```

按提示完成模型、通道等配置。完成后可再次执行 `docker compose up -d openclaw-gateway` 启动网关。

## 通道登录示例

- **WhatsApp（扫码）**  
  ```bash
  docker compose run --rm openclaw-cli channels login
  ```
- **Telegram**  
  ```bash
  docker compose run --rm openclaw-cli channels add --channel telegram --token "YOUR_BOT_TOKEN"
  ```
- **Discord**  
  ```bash
  docker compose run --rm openclaw-cli channels add --channel discord --token "YOUR_BOT_TOKEN"
  ```

更多通道与配置见 [官方文档 · Channels](https://docs.clawd.bot/channels)。

## 常用命令

| 说明           | 命令 |
|----------------|------|
| 启动 Gateway  | `docker compose up -d openclaw-gateway` |
| 查看日志      | `docker compose logs -f openclaw-gateway` |
| 停止          | `docker compose down` |
| 健康检查      | `docker compose exec openclaw-gateway node dist/index.js health --token "$OPENCLAW_GATEWAY_TOKEN"` |
| 使用 CLI 发消息 | `docker compose run --rm openclaw-cli message send --to +1234567890 --message "Hello"` |

## 环境变量说明

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `OPENCLAW_IMAGE` | `openclaw:local` | 使用的镜像名（不设则本地构建） |
| `OPENCLAW_VERSION` | `main` | 构建时克隆的 openclaw 分支/tag |
| `OPENCLAW_CONFIG_DIR` | `./data/openclaw` | 宿主机配置目录（挂载为 ~/.openclaw） |
| `OPENCLAW_WORKSPACE_DIR` | `./data/workspace` | 宿主机工作区目录 |
| `OPENCLAW_GATEWAY_PORT` | `18789` | Gateway 端口 |
| `OPENCLAW_GATEWAY_BIND` | `lan` | 绑定方式：`loopback` / `lan` |
| `OPENCLAW_GATEWAY_TOKEN` | （空） | Gateway 访问令牌，建议设置 |

更多见 `.env.example` 内注释。

## 参考

- [OpenClaw 官方 Docker 文档](https://docs.clawd.bot/install/docker)
- [OpenClaw 配置说明](https://docs.clawd.bot/gateway/configuration)
- [环境变量](https://docs.clawd.bot/environment)

## 许可证

本仓库采用 Apache-2.0。OpenClaw 项目采用 MIT 许可证。
