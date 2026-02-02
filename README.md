# docker-openclawd 🦞

> **🚀 一键安装 OpenClawd（原名Clawdbot）的 Docker 部署方案** | 自动配置，开箱即用

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
![Docker Compose](https://img.shields.io/badge/docker--compose-v2-blue.svg)

**OpenClawd** 是自托管个人 AI 助手，支持 WhatsApp / Telegram / Discord / Slack / 飞书等通道，对接 Pi 等 Agent。

## ✨ 特性

- 🎯 **一行命令安装**：无需手动配置，自动完成所有设置
- ⚙️ **自动配置**：首次运行自动执行 onboarding，创建最小配置
- 📦 **自动安装插件**：自动安装飞书插件，支持飞书/Lark 通道
- 🐳 **完整 Docker 方案**：无需在宿主机安装 Node.js 或全局包
- 🔒 **权限优化**：使用非 root 用户运行，更安全

**官方文档**：[docs.clawd.bot](https://docs.clawd.bot/) · [GitHub openclaw/openclaw](https://github.com/openclaw/openclaw)

## 前置要求

- Docker Desktop 或 Docker Engine + Docker Compose v2
- 从本地源码构建：`openclaw-src/` 不存在时，一键脚本会自动克隆 [openclaw/openclaw](https://github.com/openclaw/openclaw)，无需手动准备

## 🚀 快速开始

### 一行命令安装（推荐）

**复制以下命令，一键完成所有安装和配置：**

```bash
# macOS/Linux:
git clone https://github.com/liam798/docker-openclawd.git && cd docker-openclawd && ./docker-setup.sh

# Windows (PowerShell):
git clone https://github.com/liam798/docker-openclawd.git; cd docker-openclawd; .\docker-setup.bat

# Windows (CMD):
git clone https://github.com/liam798/docker-openclawd.git && cd docker-openclawd && docker-setup.bat
```

**脚本会自动完成：**
- ✅ 自动克隆 OpenClaw 源码（若不存在）
- ✅ 创建 `.env` 并生成 Gateway 令牌
- ✅ 构建 Docker 镜像
- ✅ 启动 Gateway 服务
- ✅ 自动安装飞书插件
- ✅ **自动执行 onboarding 配置**（首次运行）

**🎉 安装完成后即可使用！** 访问 `http://127.0.0.1:18789/` 打开 Control UI。

### 或分步手动安装

如需分步执行，可参考下方命令：

```bash
git clone https://github.com/liam798/docker-openclawd.git
cd docker-openclawd
# macOS/Linux:
./docker-setup.sh
# Windows:
docker-setup.bat
```

**方式二：手动编译安装**

```bash
# 1. 克隆本仓库
git clone https://github.com/liam798/docker-openclawd.git
cd docker-openclawd

# 2. 若没有 openclaw-src/，需先克隆（或直接运行 docker-setup.sh 自动完成）
# git clone --depth 1 https://github.com/openclaw/openclaw.git openclaw-src

# 3. 复制环境变量并（可选）编辑
cp .env.example .env
# 建议生成并填写 OPENCLAW_GATEWAY_TOKEN，例如: openssl rand -hex 24

# 4. 构建并启动 Gateway
docker compose build
docker compose up -d openclaw-gateway
```

启动后：

- **Control UI（仪表盘）**：浏览器打开 `http://127.0.0.1:18789/`（或宿主机 IP:18789）
- 若设置了 `OPENCLAW_GATEWAY_TOKEN`，在 Control UI 的「设置 → token」中填入该令牌

配置与工作区会持久化在 `./data/openclaw` 与 `./data/workspace`（可在 `.env` 中修改 `OPENCLAW_CONFIG_DIR` / `OPENCLAW_WORKSPACE_DIR`）。

## 首次配置（Onboarding）

**一键脚本会自动执行 onboarding**，创建最小配置并启动 Gateway。

如需完整配置向导（模型、通道等），可手动执行：

```bash
docker compose run --rm openclaw-cli onboard
```

按提示完成模型、通道等配置。配置会自动保存，无需重启 Gateway。

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
- **飞书（Feishu）**  
  飞书插件会在首次启动时自动安装。配置步骤：
  
  1. 在 [飞书开放平台](https://open.feishu.cn/) 创建自建应用，获取 App ID 和 App Secret
  2. 配置事件订阅（必需）：在应用后台 → 事件与回调 → 选择「长连接」，添加 `im.message.receive_v1` 事件
  3. 申请所需权限（见下方）
  4. 配置插件：
     ```bash
     docker compose run --rm openclaw-cli config set channels.feishu.appId "cli_xxxxx"
     docker compose run --rm openclaw-cli config set channels.feishu.appSecret "your_app_secret"
     docker compose run --rm openclaw-cli config set channels.feishu.enabled true
     ```
  5. 重启 Gateway：
     ```bash
     docker compose restart openclaw-gateway
     ```
  
  **必需权限**：
  - `contact:user.base:readonly` - 用户信息
  - `im:message` - 消息
  - `im:message.p2p_msg:readonly` - 私聊
  - `im:message.group_at_msg:readonly` - 群聊 @ 消息
  - `im:message:send_as_bot` - 发送消息
  - `im:resource` - 媒体资源
  
  详细配置与权限说明见 [飞书插件文档](https://github.com/m1heng/clawdbot-feishu)。

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
